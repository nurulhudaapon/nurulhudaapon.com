const std = @import("std");
const zx = @import("zx");
const github = @import("../github.zig");

pub const Archive = struct {
    files: std.StringArrayHashMapUnmanaged([]u8) = .empty,

    pub fn get(archive: *const Archive, path: []const u8) ?[]const u8 {
        return archive.files.get(path);
    }

    // `path\nlen\ncontent` per file; paths never contain newlines.
    fn encode(archive: Archive, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        var it = archive.files.iterator();
        while (it.next()) |entry| {
            try out.writer.print("{s}\n{d}\n{s}", .{ entry.key_ptr.*, entry.value_ptr.len, entry.value_ptr.* });
        }
        return out.toOwnedSlice();
    }

    fn decode(allocator: std.mem.Allocator, data: []u8) !Archive {
        var archive: Archive = .{};
        var rest = data;
        while (rest.len > 0) {
            const path_end = std.mem.indexOfScalar(u8, rest, '\n') orelse return error.InvalidCachedArchive;
            const path = rest[0..path_end];
            rest = rest[path_end + 1 ..];
            const len_end = std.mem.indexOfScalar(u8, rest, '\n') orelse return error.InvalidCachedArchive;
            const len = std.fmt.parseInt(usize, rest[0..len_end], 10) catch return error.InvalidCachedArchive;
            rest = rest[len_end + 1 ..];
            if (len > rest.len) return error.InvalidCachedArchive;
            try archive.files.put(allocator, path, rest[0..len]);
            rest = rest[len..];
        }
        return archive;
    }

    fn fromDirectory(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8) !Archive {
        var dir = try openDir(io, dir_path, .{ .iterate = true });
        defer dir.close(io);

        var archive: Archive = .{};
        errdefer {
            var it = archive.files.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            archive.files.deinit(allocator);
        }

        var it = dir.iterateAssumeFirstIteration();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".md")) continue;
            const value = try dir.readFileAlloc(io, entry.name, allocator, .unlimited);
            errdefer allocator.free(value);
            const key = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(key);
            try archive.files.put(allocator, key, value);
        }

        zx.log.debug("git: loaded {s} files={d}", .{ dir_path, archive.files.count() });
        return archive;
    }

    fn fromTarball(allocator: std.mem.Allocator, gz: []const u8) !Archive {
        var gz_reader: std.Io.Reader = .fixed(gz);
        var window: [std.compress.flate.max_window_len]u8 = undefined;
        var decompress: std.compress.flate.Decompress = .init(&gz_reader, .gzip, &window);

        var file_name_buf: [std.fs.max_path_bytes]u8 = undefined;
        var link_name_buf: [std.fs.max_path_bytes]u8 = undefined;
        var it = std.tar.Iterator.init(&decompress.reader, .{
            .file_name_buffer = &file_name_buf,
            .link_name_buffer = &link_name_buf,
        });

        var scratch: std.Io.Writer.Allocating = .init(allocator);
        defer scratch.deinit();

        var archive: Archive = .{};
        while (try it.next()) |file| {
            if (file.kind != .file) continue;
            // Tarballs nest everything under `<repo>-<ref>/`.
            const name = if (std.mem.startsWith(u8, file.name, "/")) file.name[1..] else file.name;
            const slash = std.mem.indexOfScalar(u8, name, '/') orelse continue;
            const path = name[slash + 1 ..];
            if (!std.mem.endsWith(u8, path, ".md")) continue;

            scratch.clearRetainingCapacity();
            try it.streamRemaining(file, &scratch.writer);
            try archive.files.put(allocator, try allocator.dupe(u8, path), try allocator.dupe(u8, scratch.written()));
        }

        zx.log.debug("git: extracted tarball files={d}", .{archive.files.count()});
        return archive;
    }
};

pub const Repository = struct {
    url: []const u8,
    ref: ?[]const u8 = null,

    // A `file://` URL reads `.md` files from that local directory instead of GitHub.
    pub fn archive(repo: Repository, arena: std.mem.Allocator, io: std.Io) !Archive {
        if (localPath(repo.url)) |path| return Archive.fromDirectory(arena, io, path);
        return (try Remote.init(arena, io, repo.url, repo.ref orelse "main")).archive();
    }

    // `path` is relative to the repository root.
    pub fn readFile(repo: Repository, arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
        if (!isSafeRelative(path)) return error.InvalidPath;
        if (localPath(repo.url)) |root| {
            var dir = try openDir(io, root, .{});
            defer dir.close(io);
            return dir.readFileAlloc(io, path, arena, .unlimited);
        }
        return (try Remote.init(arena, io, repo.url, repo.ref orelse "HEAD")).readFile(path);
    }
};

pub const blogs: Repository = .{
    .url = "https://github.com/nurulhudaapon/blogs",
    .ref = "main",
};

// A cached archive is trusted this long before asking GitHub whether the tip moved.
const freshness_ttl: std.Io.Duration = .fromSeconds(5 * 60);

// Raw files are also dropped whenever the archive is rebuilt for a new tip; the TTL
// keeps a failed tip check from pinning a stale file forever.
const file_ttl: std.Io.Duration = .fromSeconds(60 * 60);

const Remote = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    owner: []const u8,
    name: []const u8,
    ref: []const u8,
    kv: zx.Kv,

    fn init(arena: std.mem.Allocator, io: std.Io, url: []const u8, ref: []const u8) !Remote {
        var rest = for ([_][]const u8{ "https://github.com/", "http://github.com/", "git@github.com:" }) |prefix| {
            if (std.mem.startsWith(u8, url, prefix)) break url[prefix.len..];
        } else return error.UnsupportedRepositoryUrl;

        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return error.UnsupportedRepositoryUrl;
        const owner = rest[0..slash];
        rest = rest[slash + 1 ..];
        if (std.mem.endsWith(u8, rest, ".git")) rest = rest[0 .. rest.len - ".git".len];
        if (owner.len == 0 or rest.len == 0) return error.UnsupportedRepositoryUrl;
        return .{ .arena = arena, .io = io, .owner = owner, .name = rest, .ref = ref, .kv = zx.kv.scoped(.blogs) };
    }

    // The repo's `.md` files are cached in KV as one small blob. The tarball (mostly
    // images) is only downloaded when the branch tip moves, and the tip is checked at
    // most once per `freshness_ttl`, so a request is usually a KV read plus a parse.
    fn archive(r: Remote) !Archive {
        const archive_key = try r.key("archive");
        const sha_key = try r.key("archive-sha");
        const fresh_key = try r.key("archive-fresh");

        const cached = try r.kv.get(r.arena, archive_key);
        if (cached) |data| {
            if (try r.kv.get(r.arena, fresh_key) != null) {
                if (Archive.decode(r.arena, data)) |a| return a else |_| {}
            }
        }

        const head = r.tip() catch |err| blk: {
            zx.log.warn("git: tip check failed: {any}", .{err});
            break :blk null;
        };
        const cached_head = try r.kv.get(r.arena, sha_key);
        const unchanged = head == null or (cached_head != null and std.mem.eql(u8, cached_head.?, head.?));
        if (cached != null and unchanged) {
            if (Archive.decode(r.arena, cached.?)) |a| {
                r.kv.put(fresh_key, "1", .{ .ttl = freshness_ttl }) catch {};
                return a;
            } else |err| zx.log.warn("git: invalid cache entry: {any}", .{err});
        }

        zx.log.info("git: rebuilding from tarball (tip {s})", .{head orelse "unknown"});
        const gz = try r.get(try r.tarballUrl(), "*/*");
        defer r.arena.free(gz);
        const a = try Archive.fromTarball(r.arena, gz);

        try r.kv.put(archive_key, try a.encode(r.arena), .{});
        if (head) |sha| r.kv.put(sha_key, sha, .{}) catch {};
        r.kv.put(fresh_key, "1", .{ .ttl = freshness_ttl }) catch {};
        r.dropFiles();
        return a;
    }

    fn readFile(r: Remote, path: []const u8) ![]u8 {
        const cache_key = try r.arena.print("file:{s}/{s}:{s}:{s}", .{ r.owner, r.name, r.ref, path });
        defer r.arena.free(cache_key);

        if (try r.kv.get(r.arena, cache_key)) |cached| return cached;

        const url = try r.arena.print("https://raw.githubusercontent.com/{s}/{s}/{s}/{s}", .{ r.owner, r.name, r.ref, path });
        defer r.arena.free(url);

        const body = r.get(url, "*/*") catch |err| switch (err) {
            error.RepositoryNotFound => return error.FileNotFound,
            else => return err,
        };
        errdefer r.arena.free(body);

        try r.kv.put(cache_key, body, .{ .ttl = file_ttl });
        return body;
    }

    fn key(r: Remote, comptime kind: []const u8) ![]const u8 {
        return r.arena.print(kind ++ ":{s}/{s}:{s}", .{ r.owner, r.name, r.ref });
    }

    fn dropFiles(r: Remote) void {
        const prefix = r.arena.print("file:{s}/{s}:", .{ r.owner, r.name }) catch return;
        const keys = r.kv.list(r.arena, prefix) catch return;
        for (keys) |k| r.kv.delete(k) catch {};
    }

    fn tip(r: Remote) ![]u8 {
        const url = try r.arena.print("https://api.github.com/repos/{s}/{s}/commits/{s}", .{ r.owner, r.name, r.ref });
        defer r.arena.free(url);

        const body = try r.get(url, "application/vnd.github+json");
        defer r.arena.free(body);

        // The payload starts with {"sha":"..."}; no need to parse the whole commit.
        const needle = "\"sha\":\"";
        const start = (std.mem.indexOf(u8, body, needle) orelse return error.InvalidCommitPayload) + needle.len;
        const end = std.mem.indexOfScalarPos(u8, body, start, '"') orelse return error.InvalidCommitPayload;
        if (end <= start) return error.InvalidCommitPayload;
        return try r.arena.dupe(u8, body[start..end]);
    }

    fn tarballUrl(r: Remote) ![]const u8 {
        const ref = if (std.mem.eql(u8, r.ref, "HEAD") or std.mem.startsWith(u8, r.ref, "refs/"))
            r.ref
        else
            try r.arena.print("refs/heads/{s}", .{r.ref});
        return r.arena.print("https://codeload.github.com/{s}/{s}/tar.gz/{s}", .{ r.owner, r.name, ref });
    }

    fn get(r: Remote, url: []const u8, accept: []const u8) ![]u8 {
        var headers: std.ArrayList(zx.http.Header) = .empty;
        defer headers.deinit(r.arena);
        try headers.appendSlice(r.arena, &.{
            .{ .name = "Accept", .value = accept },
            .{ .name = "User-Agent", .value = "nurulhudaapon.com" },
        });
        if (try authorization(r.arena)) |auth| try headers.append(r.arena, .{ .name = "Authorization", .value = auth });

        var client: zx.http.Client = .{ .io = r.io, .allocator = r.arena };
        defer client.deinit();
        const response = try client.fetch(.{
            .url = url,
            .headers = headers.items,
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(120_000), .clock = .awake } },
        });
        defer response.deinit(r.arena);

        if (response.status.class() != .success) {
            zx.log.warn("git: GET {s} returned {d}", .{ url, @backingInt(response.status) });
            if (response.status == .not_found) return error.RepositoryNotFound;
            return error.NetworkError;
        }
        return try r.arena.dupe(u8, response.body);
    }
};

fn authorization(arena: std.mem.Allocator) !?[]const u8 {
    if (github.authorization()) |auth| return auth;
    const token = std.mem.span(std.c.getenv("GITHUB_TOKEN") orelse return null);
    if (token.len == 0) return null;
    return try arena.print("Bearer {s}", .{token});
}

fn localPath(url: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, url, "file://")) return null;
    const path = url["file://".len..];
    return if (path.len > 0) path else null;
}

fn openDir(io: std.Io, path: []const u8, options: std.Io.Dir.OpenOptions) !std.Io.Dir {
    if (std.fs.path.isAbsolute(path)) return std.Io.Dir.openDirAbsolute(io, path, options);
    return std.Io.Dir.cwd().openDir(io, path, options);
}

fn isSafeRelative(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\') return false;
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

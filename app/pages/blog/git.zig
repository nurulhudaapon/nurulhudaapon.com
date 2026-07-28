const std = @import("std");
const zx = @import("zx");

pub const Archive = struct {
    files: std.StringArrayHashMapUnmanaged([]u8),

    pub fn get(self: *const Archive, path: []const u8) ?[]const u8 {
        return self.files.get(path);
    }
};

pub const Repository = struct {
    url: []const u8 = "",
    ref: ?[]const u8 = null,
};

const default_repo: Repository = .{
    .url = "https://github.com/nurulhudaapon/blogs",
    .ref = "main",
    // .url = "file://../blogs",
};

/// Load `.md` files from a local `file://` directory, or download a repository
/// (cached in `zx.kv`) and return an in-memory archive.
pub fn fetchArchive(allocator: std.mem.Allocator, repo: Repository) !Archive {
    if (fileUrlPath(repo.url)) |local_path| {
        const archive = try archiveFromDirectory(allocator, local_path);
        zx.log.debug("git.fetchArchive: loaded local path={s} files={d}", .{
            local_path,
            archive.files.count(),
        });
        return archive;
    }

    const gz = try fetchTarballCached(allocator, repo);
    defer allocator.free(gz);
    return try archiveFromTarball(allocator, gz);
}

pub fn fetchDefaultArchive(allocator: std.mem.Allocator) !Archive {
    return fetchArchive(allocator, default_repo);
}

/// Read top-level `.md` files from a local directory into an archive.
pub fn archiveFromDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !Archive {
    const io = std.Io.Threaded.global_single_threaded.io();

    var dir = if (std.fs.path.isAbsolute(dir_path))
        try std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true })
    else
        try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var archive: Archive = .{ .files = .empty };
    errdefer {
        var it = archive.files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        archive.files.deinit(allocator);
    }

    var file_count: usize = 0;
    var total_bytes: usize = 0;
    var skipped_non_md: usize = 0;

    var it = dir.iterateAssumeFirstIteration();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) {
            skipped_non_md += 1;
            continue;
        }

        const value = try dir.readFileAlloc(io, entry.name, allocator, .unlimited);
        errdefer allocator.free(value);
        const key = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(key);
        try archive.files.put(allocator, key, value);
        file_count += 1;
        total_bytes += value.len;
    }

    zx.log.debug("git.archiveFromDirectory: path={s} files={d} bytes={d} skipped={d}", .{
        dir_path,
        file_count,
        total_bytes,
        skipped_non_md,
    });
    return archive;
}

/// Local blogs directory from `default_repo`'s `file://` URL, if configured.
pub fn defaultLocalPath() ?[]const u8 {
    return fileUrlPath(default_repo.url);
}

/// Read a file from the blogs repo (`file://` disk or GitHub raw + KV cache).
/// `relative_path` must be a safe relative path (no `..`, no absolute).
pub fn readRepoFile(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    if (!isSafeRelativePath(relative_path)) return error.InvalidPath;

    if (fileUrlPath(default_repo.url)) |root| {
        return try readLocalFile(allocator, root, relative_path);
    }

    return try fetchRemoteFileCached(allocator, default_repo, relative_path);
}

fn readLocalFile(allocator: std.mem.Allocator, root: []const u8, relative_path: []const u8) ![]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = if (std.fs.path.isAbsolute(root))
        try std.Io.Dir.openDirAbsolute(io, root, .{})
    else
        try std.Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);

    return try dir.readFileAlloc(io, relative_path, allocator, .unlimited);
}

fn fetchRemoteFileCached(allocator: std.mem.Allocator, repo: Repository, relative_path: []const u8) ![]u8 {
    const parsed = try parseGitHubUrl(repo.url);
    const ref = repo.ref orelse "HEAD";
    const cache_key = try std.fmt.allocPrint(allocator, "file:{s}/{s}:{s}:{s}", .{
        parsed.owner,
        parsed.repo,
        ref,
        relative_path,
    });
    defer allocator.free(cache_key);

    const blogs_kv = zx.kv.scoped(.blogs);
    if (try blogs_kv.get(allocator, cache_key)) |cached| {
        zx.log.debug("git.fetchRemoteFileCached: kv hit key={s} bytes={d}", .{ cache_key, cached.len });
        return cached;
    }

    const url = try std.fmt.allocPrint(
        allocator,
        "https://raw.githubusercontent.com/{s}/{s}/{s}/{s}",
        .{ parsed.owner, parsed.repo, ref, relative_path },
    );
    defer allocator.free(url);

    zx.log.debug("git.fetchRemoteFileCached: kv miss key={s}, downloading", .{cache_key});
    const body = fetchBytes(allocator, url, .{}) catch |err| switch (err) {
        error.RepositoryNotFound => return error.FileNotFound,
        else => return err,
    };
    errdefer allocator.free(body);

    try blogs_kv.put(cache_key, body, .{});
    return body;
}

fn isSafeRelativePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return false;
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn fileUrlPath(url: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, url, "file://")) return null;
    const path = url["file://".len..];
    return if (path.len > 0) path else null;
}

/// Fetch the raw GitHub tarball bytes, using `zx.kv` as a persistent cache.
pub fn fetchTarballCached(allocator: std.mem.Allocator, repo: Repository) ![]u8 {
    const parsed = try parseGitHubUrl(repo.url);
    const ref = try normalizeTarballRef(allocator, repo.ref orelse "HEAD");
    defer if (!std.mem.eql(u8, ref, "HEAD")) allocator.free(ref);

    const cache_key = try std.fmt.allocPrint(
        allocator,
        "tarball:{s}/{s}:{s}",
        .{ parsed.owner, parsed.repo, ref },
    );
    defer allocator.free(cache_key);

    const blogs_kv = zx.kv.scoped(.blogs);
    if (try blogs_kv.get(allocator, cache_key)) |cached| {
        defer allocator.free(cached);
        zx.log.debug("git.fetchTarballCached: kv hit key={s} bytes={d}", .{ cache_key, cached.len });
        if (decodeCachedTarball(allocator, cached)) |gz| {
            return gz;
        } else |err| {
            zx.log.warn("git.fetchTarballCached: invalid cache entry key={s} err={any}, refetching", .{ cache_key, err });
            blogs_kv.delete(cache_key) catch {};
        }
    }

    zx.log.debug("git.fetchTarballCached: kv miss key={s}, downloading", .{cache_key});
    const gz = try fetchTarball(allocator, parsed, ref);
    errdefer allocator.free(gz);

    const encoded = try encodeCachedTarball(allocator, gz);
    defer allocator.free(encoded);
    try blogs_kv.put(cache_key, encoded, .{});
    zx.log.debug("git.fetchTarballCached: stored in kv key={s} raw={d} encoded={d}", .{ cache_key, gz.len, encoded.len });
    return gz;
}

fn encodeCachedTarball(allocator: std.mem.Allocator, gz: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const out = try allocator.alloc(u8, enc.calcSize(gz.len));
    _ = enc.encode(out, gz);
    return out;
}

fn decodeCachedTarball(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const dec = std.base64.standard.Decoder;
    const out_len = try dec.calcSizeForSlice(encoded);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);
    try dec.decode(out, encoded);
    if (out.len < 2 or out[0] != 0x1f or out[1] != 0x8b) return error.InvalidCachedTarball;
    return out;
}

pub fn archiveFromTarball(allocator: std.mem.Allocator, gz: []const u8) !Archive {
    var gz_reader: std.Io.Reader = .fixed(gz);
    var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&gz_reader, .gzip, &decompress_buf);

    const archive = try extractTar(allocator, &decompress.reader);
    zx.log.debug("git.archiveFromTarball: extracted files={d}", .{archive.files.count()});
    return archive;
}

fn fetchTarball(allocator: std.mem.Allocator, parsed: GitHubRepo, ref: []const u8) ![]u8 {
    zx.log.debug("git.fetchTarball: owner={s} repo={s} ref={s}", .{ parsed.owner, parsed.repo, ref });

    const tarball_url = try std.fmt.allocPrint(
        allocator,
        "https://codeload.github.com/{s}/{s}/tar.gz/{s}",
        .{ parsed.owner, parsed.repo, ref },
    );
    defer allocator.free(tarball_url);

    const gz = try fetchBytes(allocator, tarball_url, .{});
    zx.log.debug("git.fetchTarball: fetched tarball bytes={d}", .{gz.len});
    return gz;
}

const GitHubRepo = struct {
    owner: []const u8,
    repo: []const u8,
};

fn parseGitHubUrl(url: []const u8) !GitHubRepo {
    var rest = url;
    if (std.mem.startsWith(u8, rest, "https://github.com/")) {
        rest = rest["https://github.com/".len..];
    } else if (std.mem.startsWith(u8, rest, "http://github.com/")) {
        rest = rest["http://github.com/".len..];
    } else if (std.mem.startsWith(u8, rest, "git@github.com:")) {
        rest = rest["git@github.com:".len..];
    } else {
        return error.UnsupportedRepositoryUrl;
    }

    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return error.UnsupportedRepositoryUrl;
    const owner = rest[0..slash];
    var repo = rest[slash + 1 ..];
    if (std.mem.endsWith(u8, repo, ".git")) repo = repo[0 .. repo.len - ".git".len];
    if (owner.len == 0 or repo.len == 0) return error.UnsupportedRepositoryUrl;
    return .{ .owner = owner, .repo = repo };
}

fn normalizeTarballRef(allocator: std.mem.Allocator, ref: []const u8) ![]const u8 {
    if (std.mem.eql(u8, ref, "HEAD")) return ref;
    if (std.mem.startsWith(u8, ref, "refs/")) return try allocator.dupe(u8, ref);
    return try std.fmt.allocPrint(allocator, "refs/heads/{s}", .{ref});
}

const FetchOpts = struct {
    accept: []const u8 = "*/*",
};

fn fetchBytes(allocator: std.mem.Allocator, url: []const u8, opts: FetchOpts) ![]u8 {
    zx.log.debug("git.fetchBytes: GET {s}", .{url});
    var headers_buf: [3]zx.Fetch.RequestInit.Header = undefined;
    var headers_len: usize = 0;

    headers_buf[headers_len] = .{ .name = "Accept", .value = opts.accept };
    headers_len += 1;
    headers_buf[headers_len] = .{ .name = "User-Agent", .value = "ziex-example-blog" };
    headers_len += 1;

    var auth: ?[]const u8 = null;
    defer if (auth) |a| allocator.free(a);

    if (std.c.getenv("GITHUB_TOKEN")) |token_c| {
        const token = std.mem.span(token_c);
        if (token.len > 0) {
            auth = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
            headers_buf[headers_len] = .{ .name = "Authorization", .value = auth.? };
            headers_len += 1;
        }
    }

    var response = (try zx.fetch(.blocking, allocator, url, .{
        .headers = headers_buf[0..headers_len],
        .timeout_ms = 120_000,
    })) orelse return error.NetworkError;
    defer response.deinit();

    if (!response.ok()) {
        zx.log.warn("git.fetchBytes: response status={d} url={s}", .{ response.status, url });
        if (response.status == 404) return error.RepositoryNotFound;
        return error.NetworkError;
    }

    const body = try response.bytes();
    zx.log.debug("git.fetchBytes: response status={d} bytes={d}", .{ response.status, body.len });
    return try allocator.dupe(u8, body);
}

fn extractTar(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Archive {
    var archive: Archive = .{ .files = .empty };
    var file_count: usize = 0;
    var total_bytes: usize = 0;
    var skipped_non_md: usize = 0;

    var file_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var it = std.tar.Iterator.init(reader, .{
        .file_name_buffer = &file_name_buf,
        .link_name_buffer = &link_name_buf,
    });

    var scratch = std.Io.Writer.Allocating.init(allocator);
    defer scratch.deinit();

    zx.log.debug("git.extractTar: start", .{});

    while (try it.next()) |file| {
        if (file.kind != .file) continue;
        const stripped = stripComponents(file.name, 1) orelse continue;
        if (stripped.len == 0) continue;
        if (!std.mem.endsWith(u8, stripped, ".md")) {
            skipped_non_md += 1;
            continue;
        }

        scratch.clearRetainingCapacity();
        try it.streamRemaining(file, &scratch.writer);

        const key = try allocator.dupe(u8, stripped);
        const value = try allocator.dupe(u8, scratch.written());
        try archive.files.put(allocator, key, value);
        file_count += 1;
        total_bytes += value.len;
    }

    zx.log.debug("git.extractTar: done files={d} bytes={d} skipped={d}", .{
        file_count,
        total_bytes,
        skipped_non_md,
    });
    return archive;
}

fn stripComponents(path: []const u8, count: u32) ?[]const u8 {
    var rest = path;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (rest.len > 0 and rest[0] == '/') rest = rest[1..];
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
        rest = rest[slash + 1 ..];
    }
    return rest;
}

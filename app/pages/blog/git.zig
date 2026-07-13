const std = @import("std");
const zx = @import("zx");

pub const Archive = struct {
    files: std.StringArrayHashMapUnmanaged([]u8),

    pub fn get(self: *const Archive, path: []const u8) ?[]const u8 {
        return self.files.get(path);
    }
};

pub const Repository = struct {
    url: []const u8,
    ref: ?[]const u8 = null,
};

const default_repo: Repository = .{
    .url = "https://github.com/nurulhudaapon/blogs",
    .ref = "main",
};

/// Download a repository (or load a cached tarball from `zx.kv`) and return
/// an in-memory archive of its `.md` files.
pub fn fetchArchive(allocator: std.mem.Allocator, repo: Repository) !Archive {
    const gz = try fetchTarballCached(allocator, repo);
    defer allocator.free(gz);
    return try archiveFromTarball(allocator, gz);
}

pub fn fetchDefaultArchive(allocator: std.mem.Allocator) !Archive {
    return fetchArchive(allocator, default_repo);
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
        zx.log.debug("git.fetchTarballCached: kv hit key={s} bytes={d}", .{ cache_key, cached.len });
        return cached;
    }

    zx.log.debug("git.fetchTarballCached: kv miss key={s}, downloading", .{cache_key});
    const gz = try fetchTarball(allocator, parsed, ref);
    errdefer allocator.free(gz);

    try blogs_kv.put(cache_key, gz, .{});
    zx.log.debug("git.fetchTarballCached: stored in kv key={s} bytes={d}", .{ cache_key, gz.len });
    return gz;
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

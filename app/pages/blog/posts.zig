const std = @import("std");
const git = @import("git.zig");
const render = @import("render.zig");
const hashnode = @import("hashnode.zig");

pub const GetPostError = error{
    FailedToFetchPosts,
    FailedToParsePosts,
    OutOfMemory,
    PostNotFound,
};

pub const Post = struct {
    id: []const u8,
    title: []const u8,
    brief: []const u8,
    url: []const u8,
    slug: []const u8,
    publishedAt: []const u8,
    readTimeInMinutes: u32,
    views: u32 = 0,
    subtitle: ?[]const u8 = null,
    coverImage: ?[]const u8 = null,
    content: ?[]const u8 = null,
    author: struct {
        name: []const u8,
        username: ?[]const u8 = null,
        profilePicture: ?[]const u8 = null,
    },
};

const Frontmatter = struct {
    title: ?[]const u8 = null,
    slug: ?[]const u8 = null,
    cuid: ?[]const u8 = null,
    date_published: ?[]const u8 = null,
    cover: ?[]const u8 = null,
    seo_description: ?[]const u8 = null,
    seo_title: ?[]const u8 = null,
};

pub fn getPosts(allocator: std.mem.Allocator) GetPostError![]Post {
    const archive = git.fetchDefaultArchive(allocator) catch |err| {
        std.log.err("Failed to fetch blog archive: {any}", .{err});
        return error.FailedToFetchPosts;
    };

    var posts: std.ArrayList(Post) = .empty;
    errdefer posts.deinit(allocator);

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        const path = entry.key_ptr.*;
        if (std.mem.startsWith(u8, path, "draft-")) continue;

        const basename = std.fs.path.basename(path);
        const post = parsePost(allocator, basename, entry.value_ptr.*, false) catch |err| {
            std.log.warn("Skipping {s}: {any}", .{ path, err });
            continue;
        };
        try posts.append(allocator, post);
    }

    const slice = try posts.toOwnedSlice(allocator);
    sortPostsNewestFirst(slice);
    return slice;
}

pub fn getPostBySlug(allocator: std.mem.Allocator, slug: []const u8) GetPostError!Post {
    const archive = git.fetchDefaultArchive(allocator) catch |err| {
        std.log.err("Failed to fetch blog archive: {any}", .{err});
        return error.FailedToFetchPosts;
    };

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        const path = entry.key_ptr.*;
        if (std.mem.startsWith(u8, path, "draft-")) continue;

        const basename = std.fs.path.basename(path);
        const fm = parseFrontmatter(entry.value_ptr.*) catch continue;
        const file_slug = fm.slug orelse slugFromFilename(basename) orelse continue;
        if (!std.mem.eql(u8, file_slug, slug)) continue;

        return parsePost(allocator, basename, entry.value_ptr.*, true) catch |err| {
            std.log.err("Failed to parse post {s}: {any}", .{ path, err });
            return error.FailedToParsePosts;
        };
    }

    return error.PostNotFound;
}

/// Collect catch-all image params (`hn/v…/file.png`) from all published posts.
pub fn collectHashnodeImageParams(allocator: std.mem.Allocator) GetPostError![][]const u8 {
    const archive = git.fetchDefaultArchive(allocator) catch |err| {
        std.log.err("Failed to fetch blog archive for images: {any}", .{err});
        return error.FailedToFetchPosts;
    };

    var sources: std.ArrayList([]const u8) = .empty;
    defer sources.deinit(allocator);

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        const path = entry.key_ptr.*;
        if (std.mem.startsWith(u8, path, "draft-")) continue;
        try sources.append(allocator, entry.value_ptr.*);
    }

    return hashnode.collectStaticParamPaths(allocator, sources.items) catch |err| {
        std.log.err("Failed to collect hashnode image paths: {any}", .{err});
        return error.OutOfMemory;
    };
}

fn parsePost(allocator: std.mem.Allocator, filename: []const u8, source: []const u8, with_html: bool) !Post {
    const split = try splitFrontmatter(source);
    const fm = try parseFrontmatterFields(split.meta);

    const title = fm.title orelse return error.FailedToParsePosts;
    const slug = fm.slug orelse slugFromFilename(filename) orelse return error.FailedToParsePosts;
    const id = fm.cuid orelse slug;
    const published_raw = fm.date_published orelse "Draft";

    const body = std.mem.trim(u8, split.body, " \t\r\n");
    const brief = if (fm.seo_description) |desc|
        try allocator.dupe(u8, desc)
    else
        try makeBrief(allocator, body);

    const content: ?[]const u8 = if (with_html)
        try render.renderMarkdown(allocator, body)
    else
        null;

    return .{
        .id = try allocator.dupe(u8, id),
        .title = try allocator.dupe(u8, title),
        .brief = brief,
        .url = try std.fmt.allocPrint(allocator, "/blog/{s}", .{slug}),
        .slug = try allocator.dupe(u8, slug),
        .publishedAt = try formatPublishedDate(allocator, published_raw),
        .readTimeInMinutes = estimateReadTime(body),
        .subtitle = if (fm.seo_title) |st| try allocator.dupe(u8, st) else null,
        .coverImage = if (fm.cover) |c| blk: {
            break :blk (try hashnode.localizeUrl(allocator, c)) orelse try allocator.dupe(u8, c);
        } else null,
        .content = content,
        .author = .{
            .name = "Nurul Huda (Apon)",
            .username = "nurulhudaapon",
            .profilePicture = null,
        },
    };
}

fn splitFrontmatter(source: []const u8) !struct { meta: []const u8, body: []const u8 } {
    const trimmed = std.mem.trimStart(u8, source, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "---")) return error.FailedToParsePosts;

    const after_open = trimmed[3..];
    const close = std.mem.indexOf(u8, after_open, "\n---") orelse return error.FailedToParsePosts;
    const meta = std.mem.trim(u8, after_open[0..close], " \t\r\n");
    var body = after_open[close + "\n---".len ..];
    if (std.mem.startsWith(u8, body, "\r")) body = body[1..];
    if (std.mem.startsWith(u8, body, "\n")) body = body[1..];
    return .{ .meta = meta, .body = body };
}

fn parseFrontmatter(source: []const u8) !Frontmatter {
    const split = try splitFrontmatter(source);
    return try parseFrontmatterFields(split.meta);
}

fn parseFrontmatterFields(meta: []const u8) !Frontmatter {
    var fm: Frontmatter = .{};
    var lines = std.mem.splitScalar(u8, meta, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = unwrapQuotes(std.mem.trim(u8, line[colon + 1 ..], " \t"));

        if (std.mem.eql(u8, key, "title")) {
            fm.title = value;
        } else if (std.mem.eql(u8, key, "slug")) {
            fm.slug = value;
        } else if (std.mem.eql(u8, key, "cuid")) {
            fm.cuid = value;
        } else if (std.mem.eql(u8, key, "datePublished")) {
            fm.date_published = value;
        } else if (std.mem.eql(u8, key, "cover")) {
            fm.cover = value;
        } else if (std.mem.eql(u8, key, "seoDescription")) {
            fm.seo_description = value;
        } else if (std.mem.eql(u8, key, "seoTitle")) {
            fm.seo_title = value;
        }
    }
    return fm;
}

fn unwrapQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn slugFromFilename(filename: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, filename, ".md")) return null;
    const stem = filename[0 .. filename.len - ".md".len];
    if (stem.len == 0) return null;
    return stem;
}

fn makeBrief(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    var start: usize = 0;
    while (start < body.len and std.ascii.isWhitespace(body[start])) : (start += 1) {}

    var end = start;
    while (end < body.len and body[end] != '\n') : (end += 1) {}

    var excerpt = std.mem.trim(u8, body[start..end], " \t\r");
    // Strip simple markdown heading markers / emphasis for the listing brief.
    if (std.mem.startsWith(u8, excerpt, "#")) {
        excerpt = std.mem.trimStart(u8, excerpt, "# ");
    }

    const max_len: usize = 220;
    if (excerpt.len <= max_len) return try allocator.dupe(u8, excerpt);

    var cut = max_len;
    while (cut > 0 and !std.ascii.isWhitespace(excerpt[cut])) : (cut -= 1) {}
    if (cut == 0) cut = max_len;
    return try std.fmt.allocPrint(allocator, "{s}…", .{excerpt[0..cut]});
}

fn estimateReadTime(body: []const u8) u32 {
    var words: u32 = 0;
    var in_word = false;
    for (body) |c| {
        if (std.ascii.isWhitespace(c)) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            words += 1;
        }
    }
    const minutes = (words + 199) / 200;
    return if (minutes == 0) 1 else minutes;
}

fn sortPostsNewestFirst(posts: []Post) void {
    std.mem.sort(Post, posts, {}, struct {
        fn lessThan(_: void, a: Post, b: Post) bool {
            return comparePublishedDesc(a.publishedAt, b.publishedAt);
        }
    }.lessThan);
}

fn comparePublishedDesc(a: []const u8, b: []const u8) bool {
    const ta = parsePublishedSortKey(a);
    const tb = parsePublishedSortKey(b);
    if (ta != tb) return ta > tb;
    return std.mem.order(u8, a, b) == .gt;
}

/// Sort key from published date strings (JS Date, ISO, or display `Jan 30, 2026`).
fn parsePublishedSortKey(date: []const u8) u64 {
    if (date.len >= 10 and date[4] == '-' and date[7] == '-') {
        const year = std.fmt.parseInt(u64, date[0..4], 10) catch return 0;
        const month = std.fmt.parseInt(u64, date[5..7], 10) catch return 0;
        const day = std.fmt.parseInt(u64, date[8..10], 10) catch return 0;
        return ((year * 100 + month) * 100 + day) * 1000000;
    }

    if (std.mem.indexOf(u8, date, ", ")) |_| {
        var parts = std.mem.tokenizeAny(u8, date, " ,");
        const month_name = parts.next() orelse return 0;
        const day_s = parts.next() orelse return 0;
        const year_s = parts.next() orelse return 0;
        const month: u64 = monthIndex(month_name) orelse return 0;
        const day = std.fmt.parseInt(u64, day_s, 10) catch return 0;
        const year = std.fmt.parseInt(u64, year_s, 10) catch return 0;
        return ((year * 100 + month) * 100 + day) * 1000000;
    }

    var parts = std.mem.tokenizeAny(u8, date, " ");
    _ = parts.next(); // weekday
    const month_name = parts.next() orelse return 0;
    const day_s = parts.next() orelse return 0;
    const year_s = parts.next() orelse return 0;
    const time_s = parts.next() orelse return 0;

    const month: u64 = monthIndex(month_name) orelse return 0;
    const day = std.fmt.parseInt(u64, day_s, 10) catch return 0;
    const year = std.fmt.parseInt(u64, year_s, 10) catch return 0;

    var time_parts = std.mem.splitScalar(u8, time_s, ':');
    const hour = std.fmt.parseInt(u64, time_parts.next() orelse "0", 10) catch 0;
    const minute = std.fmt.parseInt(u64, time_parts.next() orelse "0", 10) catch 0;
    const second = std.fmt.parseInt(u64, time_parts.next() orelse "0", 10) catch 0;

    return (((((year * 100 + month) * 100 + day) * 100 + hour) * 100 + minute) * 100 + second);
}

fn formatPublishedDate(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "Draft")) return try allocator.dupe(u8, raw);

    if (raw.len >= 10 and raw[4] == '-' and raw[7] == '-') {
        const year = raw[0..4];
        const month = std.fmt.parseInt(u8, raw[5..7], 10) catch return try allocator.dupe(u8, raw);
        const day = std.fmt.parseInt(u8, raw[8..10], 10) catch return try allocator.dupe(u8, raw);
        const month_name = monthName(month) orelse return try allocator.dupe(u8, raw);
        return try std.fmt.allocPrint(allocator, "{s} {d}, {s}", .{ month_name, day, year });
    }

    var parts = std.mem.tokenizeAny(u8, raw, " ");
    _ = parts.next(); // weekday
    const month_name = parts.next() orelse return try allocator.dupe(u8, raw);
    const day_s = parts.next() orelse return try allocator.dupe(u8, raw);
    const year_s = parts.next() orelse return try allocator.dupe(u8, raw);
    const day = std.fmt.parseInt(u32, day_s, 10) catch return try allocator.dupe(u8, raw);
    return try std.fmt.allocPrint(allocator, "{s} {d}, {s}", .{ month_name, day, year_s });
}

fn monthName(index: u8) ?[]const u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    if (index < 1 or index > 12) return null;
    return months[index - 1];
}

fn monthIndex(name: []const u8) ?u64 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (months, 1..) |m, i| {
        if (std.mem.eql(u8, m, name)) return i;
    }
    return null;
}

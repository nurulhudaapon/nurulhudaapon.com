const std = @import("std");
const git = @import("git.zig");
const render = @import("render.zig");

pub const Error = error{
    FailedToFetchPosts,
    FailedToParsePosts,
    OutOfMemory,
    PostNotFound,
};

pub const author = "Nurul Huda (Apon)";

pub const Post = struct {
    title: []const u8,
    brief: []const u8,
    url: []const u8,
    slug: []const u8,
    date: []const u8,
    read_minutes: u32,
    cover: ?[]const u8 = null,
    seo_title: ?[]const u8 = null,
    seo_description: ?[]const u8 = null,
    content: ?[]const u8 = null,
};

// The renderer is only compiled in when some caller asks for `.html`, which keeps
// markdown and tree-sitter out of binaries that never render a post.
pub const Body = enum { none, markdown, html };

pub fn list(arena: std.mem.Allocator, io: std.Io) Error![]Post {
    const archive = try fetch(arena, io);

    var out: std.ArrayList(Post) = .empty;
    errdefer out.deinit(arena);

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        const path = entry.key_ptr.*;
        if (isDraftPath(path)) continue;

        const fm = Frontmatter.parse(entry.value_ptr.*) catch |err| {
            std.log.warn("Skipping {s}: {any}", .{ path, err });
            continue;
        };
        if (fm.isDraft()) continue;

        const post = parse(arena, std.fs.path.basename(path), entry.value_ptr.*, .none) catch |err| {
            std.log.warn("Skipping {s}: {any}", .{ path, err });
            continue;
        };
        try out.append(arena, post);
    }

    const posts = try out.toOwnedSlice(arena);
    std.mem.sort(Post, posts, {}, struct {
        fn lessThan(_: void, a: Post, b: Post) bool {
            return newerFirst(a.date, b.date);
        }
    }.lessThan);
    return posts;
}

pub fn get(arena: std.mem.Allocator, io: std.Io, slug: []const u8, comptime body: Body) Error!Post {
    const archive = try fetch(arena, io);

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        const path = entry.key_ptr.*;
        if (isDraftPath(path)) continue;

        const basename = std.fs.path.basename(path);
        const fm = Frontmatter.parse(entry.value_ptr.*) catch continue;
        if (fm.isDraft()) continue;
        const file_slug = fm.slug orelse slugFromFilename(basename) orelse continue;
        if (!std.mem.eql(u8, file_slug, slug)) continue;

        return parse(arena, basename, entry.value_ptr.*, body) catch |err| {
            std.log.err("Failed to parse post {s}: {any}", .{ path, err });
            return error.FailedToParsePosts;
        };
    }

    return error.PostNotFound;
}

const image_prefix = "/blog/images/";

// Catch-all params (`v…/file.png`) for `/blog/images/[..]`.
pub fn imagePaths(arena: std.mem.Allocator, io: std.Io) Error![][]const u8 {
    const archive = try fetch(arena, io);

    var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer seen.deinit(arena);

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |p| arena.free(p);
        out.deinit(arena);
    }

    var it = archive.files.iterator();
    while (it.next()) |entry| {
        if (isDraftPath(entry.key_ptr.*)) continue;
        const fm = Frontmatter.parse(entry.value_ptr.*) catch continue;
        if (fm.isDraft()) continue;
        try appendImagePaths(arena, entry.value_ptr.*, &seen, &out);
    }

    return try out.toOwnedSlice(arena);
}

fn appendImagePaths(
    arena: std.mem.Allocator,
    markdown: []const u8,
    seen: *std.StringArrayHashMapUnmanaged(void),
    out: *std.ArrayList([]const u8),
) !void {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, markdown, start, image_prefix)) |at| {
        var end = at + image_prefix.len;
        while (end < markdown.len and !isUrlEnd(markdown[end])) : (end += 1) {}

        const rest = markdown[at + image_prefix.len .. end];
        if (rest.len > 0) {
            const key = try arena.dupe(u8, rest);
            const gop = try seen.getOrPut(arena, key);
            if (gop.found_existing) {
                arena.free(key);
            } else {
                gop.key_ptr.* = key;
                try out.append(arena, key);
            }
        }
        start = end;
    }
}

fn isUrlEnd(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r', ')', '"', '\'', '<', '>', ']', '?', '#' => true,
        else => false,
    };
}

pub const Source = struct {
    path: []const u8,
    slug: []const u8,
    title: []const u8,
    draft: bool,
    date: []const u8,
    read_minutes: u32,
    markdown: []const u8,

    fn init(path: []const u8, markdown: []const u8) ?Source {
        const basename = std.fs.path.basename(path);
        const split = Split.init(markdown) catch return null;
        const fm = Frontmatter.fromMeta(split.meta);
        return .{
            .path = path,
            .slug = fm.slug orelse slugFromFilename(basename) orelse return null,
            .title = fm.title orelse basename,
            .draft = isDraftPath(path) or fm.isDraft(),
            .date = fm.published_at orelse "",
            .read_minutes = readMinutes(split.body),
            .markdown = markdown,
        };
    }
};

pub fn sources(arena: std.mem.Allocator, io: std.Io) Error![]Source {
    const archive = try fetch(arena, io);

    var out: std.ArrayList(Source) = .empty;
    var it = archive.files.iterator();
    while (it.next()) |entry| {
        if (Source.init(entry.key_ptr.*, entry.value_ptr.*)) |src| try out.append(arena, src);
    }
    std.mem.sort(Source, out.items, {}, struct {
        fn lessThan(_: void, a: Source, b: Source) bool {
            if (a.draft != b.draft) return a.draft;
            return newerFirst(a.date, b.date);
        }
    }.lessThan);
    for (out.items) |*src| {
        if (src.date.len > 0) src.date = try formatDate(arena, src.date);
    }
    return out.toOwnedSlice(arena);
}

pub fn source(arena: std.mem.Allocator, io: std.Io, slug: []const u8) Error!Source {
    for (try sources(arena, io)) |src| if (std.mem.eql(u8, src.slug, slug)) return src;
    return error.PostNotFound;
}

pub const Preview = struct {
    title: []const u8,
    html: []const u8,
    read_minutes: u32,
};

pub fn preview(allocator: std.mem.Allocator, markdown: []const u8) !Preview {
    const split = Split.init(markdown) catch Split{ .meta = "", .body = markdown };
    const fm = Frontmatter.fromMeta(split.meta);
    const body = std.mem.trim(u8, split.body, " \t\r\n");
    return .{
        .title = fm.title orelse "",
        .html = if (body.len == 0) "" else try render.html(allocator, body),
        .read_minutes = readMinutes(body),
    };
}

fn fetch(arena: std.mem.Allocator, io: std.Io) Error!git.Archive {
    return git.blogs.archive(arena, io) catch |err| {
        std.log.err("Failed to fetch blog archive: {any}", .{err});
        return error.FailedToFetchPosts;
    };
}

fn isDraftPath(path: []const u8) bool {
    return std.mem.startsWith(u8, std.fs.path.basename(path), "draft-");
}

fn parse(arena: std.mem.Allocator, filename: []const u8, markdown: []const u8, comptime with: Body) !Post {
    const split = try Split.init(markdown);
    const fm = Frontmatter.fromMeta(split.meta);
    if (fm.isDraft()) return error.FailedToParsePosts;

    const title = fm.title orelse return error.FailedToParsePosts;
    const slug = fm.slug orelse slugFromFilename(filename) orelse return error.FailedToParsePosts;

    const body = std.mem.trim(u8, split.body, " \t\r\n");
    return .{
        .title = try arena.dupe(u8, title),
        .brief = if (fm.seo_description) |desc| try arena.dupe(u8, desc) else try brief(arena, body),
        .url = try arena.print("/blog/{s}", .{slug}),
        .slug = try arena.dupe(u8, slug),
        .date = try formatDate(arena, fm.published_at orelse "Draft"),
        .read_minutes = readMinutes(body),
        .cover = if (fm.cover) |c| try arena.dupe(u8, c) else null,
        .seo_title = if (fm.seo_title) |t| try arena.dupe(u8, t) else null,
        .seo_description = if (fm.seo_description) |d| try arena.dupe(u8, d) else null,
        .content = switch (with) {
            .none => null,
            .markdown => try arena.dupe(u8, body),
            .html => try render.html(arena, body),
        },
    };
}

const Split = struct {
    meta: []const u8,
    body: []const u8,

    fn init(markdown: []const u8) !Split {
        const trimmed = std.mem.trimStart(u8, markdown, " \t\r\n");
        if (!std.mem.startsWith(u8, trimmed, "---")) return error.FailedToParsePosts;

        const after_open = trimmed[3..];
        const close = std.mem.indexOf(u8, after_open, "\n---") orelse return error.FailedToParsePosts;
        var body = after_open[close + "\n---".len ..];
        if (std.mem.startsWith(u8, body, "\r")) body = body[1..];
        if (std.mem.startsWith(u8, body, "\n")) body = body[1..];
        return .{ .meta = std.mem.trim(u8, after_open[0..close], " \t\r\n"), .body = body };
    }
};

const Frontmatter = struct {
    title: ?[]const u8 = null,
    slug: ?[]const u8 = null,
    status: ?[]const u8 = null,
    published_at: ?[]const u8 = null,
    cover: ?[]const u8 = null,
    seo_description: ?[]const u8 = null,
    seo_title: ?[]const u8 = null,

    fn parse(markdown: []const u8) !Frontmatter {
        return fromMeta((try Split.init(markdown)).meta);
    }

    fn fromMeta(meta: []const u8) Frontmatter {
        var fm: Frontmatter = .{};
        var lines = std.mem.splitScalar(u8, meta, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = unquote(std.mem.trim(u8, line[colon + 1 ..], " \t"));
            const field = std.meta.stringToEnum(std.meta.FieldEnum(Frontmatter), key) orelse continue;
            switch (field) {
                inline else => |f| @field(fm, @tagName(f)) = value,
            }
        }
        return fm;
    }

    fn isDraft(fm: Frontmatter) bool {
        const status = fm.status orelse return false;
        return std.mem.eql(u8, status, "draft");
    }

    fn unquote(value: []const u8) []const u8 {
        if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') return value[1 .. value.len - 1];
        return value;
    }
};

fn slugFromFilename(filename: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, filename, ".md")) return null;
    const stem = filename[0 .. filename.len - ".md".len];
    return if (stem.len == 0) null else stem;
}

// Plain-text preview of the body: skips headings, embeds, images and code.
fn brief(arena: std.mem.Allocator, body: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(arena);

    const target_len: usize = 180;
    var in_fence = false;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");

        if (std.mem.startsWith(u8, line, "```")) {
            in_fence = !in_fence;
            continue;
        }
        if (in_fence or skipInBrief(line)) continue;

        const plain = try stripInline(arena, line);
        defer arena.free(plain);
        const text = std.mem.trim(u8, plain, " \t");
        if (text.len == 0) continue;

        if (out.items.len > 0) try out.append(arena, ' ');
        try out.appendSlice(arena, text);
        if (out.items.len >= target_len) break;
    }

    if (out.items.len == 0) return try arena.dupe(u8, "...");

    const max_len: usize = 160;
    if (out.items.len <= max_len) return try arena.print("{s}...", .{out.items});

    var cut = max_len;
    while (cut > 0 and !std.ascii.isWhitespace(out.items[cut])) : (cut -= 1) {}
    if (cut == 0) cut = max_len;
    while (cut > 0 and std.ascii.isWhitespace(out.items[cut - 1])) : (cut -= 1) {}
    return try arena.print("{s}...", .{out.items[0..cut]});
}

fn skipInBrief(line: []const u8) bool {
    if (line.len == 0) return true;
    if (line[0] == '#' or line[0] == '<') return true;
    if (std.mem.startsWith(u8, line, "%[") or std.mem.startsWith(u8, line, "![")) return true;
    return isRule(line);
}

fn isRule(line: []const u8) bool {
    if (line.len < 3) return false;
    const ch = line[0];
    if (ch != '-' and ch != '*' and ch != '_') return false;
    for (line) |c| if (c != ch and c != ' ') return false;
    return true;
}

fn stripInline(arena: std.mem.Allocator, line: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(arena);

    var i: usize = 0;
    // List and quote markers.
    while (i < line.len) {
        if (line[i] == '>' or line[i] == '-' or line[i] == '*') {
            i += 1;
        } else if (std.mem.startsWith(u8, line[i..], "→")) {
            i += "→".len;
        } else if (std.mem.startsWith(u8, line[i..], "•")) {
            i += "•".len;
        } else if (std.ascii.isDigit(line[i])) {
            var j = i;
            while (j < line.len and std.ascii.isDigit(line[j])) : (j += 1) {}
            if (j >= line.len or line[j] != '.') break;
            i = j + 1;
        } else break;
        while (i < line.len and line[i] == ' ') : (i += 1) {}
    }

    while (i < line.len) {
        if (line[i] == '[') link: {
            const close = std.mem.indexOfScalarPos(u8, line, i + 1, ']') orelse break :link;
            if (close + 1 >= line.len or line[close + 1] != '(') break :link;
            const paren = std.mem.indexOfScalarPos(u8, line, close + 2, ')') orelse break :link;
            try out.appendSlice(arena, line[i + 1 .. close]);
            i = paren + 1;
            continue;
        }

        if (std.mem.startsWith(u8, line[i..], "http://") or std.mem.startsWith(u8, line[i..], "https://")) {
            while (i < line.len and !std.ascii.isWhitespace(line[i]) and line[i] != ')' and line[i] != ']') : (i += 1) {}
            continue;
        }

        switch (line[i]) {
            '*', '_', '`', '~' => {},
            else => try out.append(arena, line[i]),
        }
        i += 1;
    }

    var collapsed: std.ArrayList(u8) = .empty;
    errdefer collapsed.deinit(arena);
    var prev_space = false;
    for (out.items) |c| {
        if (std.ascii.isWhitespace(c)) {
            if (!prev_space and collapsed.items.len > 0) {
                try collapsed.append(arena, ' ');
                prev_space = true;
            }
        } else {
            try collapsed.append(arena, c);
            prev_space = false;
        }
    }
    return try collapsed.toOwnedSlice(arena);
}

fn readMinutes(body: []const u8) u32 {
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
    return @max(1, (words + 199) / 200);
}

fn newerFirst(a: []const u8, b: []const u8) bool {
    const ka = sortKey(a);
    const kb = sortKey(b);
    if (ka != kb) return ka > kb;
    return std.mem.order(u8, a, b) == .gt;
}

// Accepts ISO (`2026-01-30`), display (`Jan 30, 2026`) and JS Date strings.
fn sortKey(date: []const u8) u64 {
    if (date.len >= 10 and date[4] == '-' and date[7] == '-') {
        const year = std.fmt.parseInt(u64, date[0..4], 10) catch return 0;
        const month = std.fmt.parseInt(u64, date[5..7], 10) catch return 0;
        const day = std.fmt.parseInt(u64, date[8..10], 10) catch return 0;
        return ((year * 100 + month) * 100 + day) * 1000000;
    }

    if (std.mem.indexOf(u8, date, ", ") != null) {
        var parts = std.mem.tokenizeAny(u8, date, " ,");
        const month = monthIndex(parts.next() orelse return 0) orelse return 0;
        const day = std.fmt.parseInt(u64, parts.next() orelse return 0, 10) catch return 0;
        const year = std.fmt.parseInt(u64, parts.next() orelse return 0, 10) catch return 0;
        return ((year * 100 + month) * 100 + day) * 1000000;
    }

    var parts = std.mem.tokenizeAny(u8, date, " ");
    _ = parts.next(); // weekday
    const month_name = parts.next() orelse return 0;
    const day_s = parts.next() orelse return 0;
    const year_s = parts.next() orelse return 0;
    const time_s = parts.next() orelse return 0;

    const month = monthIndex(month_name) orelse return 0;
    const day = std.fmt.parseInt(u64, day_s, 10) catch return 0;
    const year = std.fmt.parseInt(u64, year_s, 10) catch return 0;

    var time = std.mem.splitScalar(u8, time_s, ':');
    const hour = std.fmt.parseInt(u64, time.next() orelse "0", 10) catch 0;
    const minute = std.fmt.parseInt(u64, time.next() orelse "0", 10) catch 0;
    const second = std.fmt.parseInt(u64, time.next() orelse "0", 10) catch 0;

    return (((((year * 100 + month) * 100 + day) * 100 + hour) * 100 + minute) * 100 + second);
}

fn formatDate(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "Draft")) return try arena.dupe(u8, raw);

    if (raw.len >= 10 and raw[4] == '-' and raw[7] == '-') {
        const month = std.fmt.parseInt(u8, raw[5..7], 10) catch return try arena.dupe(u8, raw);
        const day = std.fmt.parseInt(u8, raw[8..10], 10) catch return try arena.dupe(u8, raw);
        if (month < 1 or month > 12) return try arena.dupe(u8, raw);
        return try arena.print("{s} {d}, {s}", .{ months[month - 1], day, raw[0..4] });
    }

    var parts = std.mem.tokenizeAny(u8, raw, " ");
    _ = parts.next(); // weekday
    const month_name = parts.next() orelse return try arena.dupe(u8, raw);
    const day_s = parts.next() orelse return try arena.dupe(u8, raw);
    const year_s = parts.next() orelse return try arena.dupe(u8, raw);
    const day = std.fmt.parseInt(u32, day_s, 10) catch return try arena.dupe(u8, raw);
    return try arena.print("{s} {d}, {s}", .{ month_name, day, year_s });
}

const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

fn monthIndex(name: []const u8) ?u64 {
    for (months, 1..) |m, i| if (std.mem.eql(u8, m, name)) return i;
    return null;
}

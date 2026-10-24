const std = @import("std");
const ts = @import("tree_sitter");

const Grammar = struct {
    names: []const []const u8,
    language: *const fn () callconv(.c) *const anyopaque,
    highlights: []const u8,
};

extern fn tree_sitter_zx() callconv(.c) *const anyopaque;
extern fn tree_sitter_javascript() callconv(.c) *const anyopaque;
extern fn tree_sitter_typescript() callconv(.c) *const anyopaque;
extern fn tree_sitter_zig() callconv(.c) *const anyopaque;
extern fn tree_sitter_bash() callconv(.c) *const anyopaque;
extern fn tree_sitter_json() callconv(.c) *const anyopaque;

const grammars = [_]Grammar{
    .{ .names = &.{"zx"}, .language = tree_sitter_zx, .highlights = @embedFile("zx.scm") },
    // TypeScript's query extends JavaScript's; later patterns win.
    .{ .names = &.{ "ts", "typescript" }, .language = tree_sitter_typescript, .highlights = @embedFile("javascript.scm") ++ @embedFile("typescript.scm") },
    .{ .names = &.{ "js", "javascript", "jsx" }, .language = tree_sitter_javascript, .highlights = @embedFile("javascript.scm") },
    .{ .names = &.{"zig"}, .language = tree_sitter_zig, .highlights = @embedFile("zig.scm") },
    .{ .names = &.{ "sh", "bash", "shell" }, .language = tree_sitter_bash, .highlights = @embedFile("bash.scm") },
    .{ .names = &.{"json"}, .language = tree_sitter_json, .highlights = @embedFile("json.scm") },
};

var queries: [grammars.len]std.atomic.Value(?*ts.Query) = @splat(.init(null));

pub fn html(allocator: std.mem.Allocator, lang: []const u8, source: []const u8) !?[]u8 {
    const index = find(lang) orelse return null;
    const language = ts.Language.fromRaw(grammars[index].language());
    const query = try getQuery(index, language);

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);
    const tree = parser.parseString(source, null) orelse return error.ParseFailed;
    defer tree.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();
    cursor.exec(query, tree.rootNode());

    var spans: std.ArrayList(Span) = .empty;
    defer spans.deinit(allocator);
    while (cursor.nextCapture()) |next| {
        const index_in_match, const match = next;
        const capture = match.captures[index_in_match];
        const name = query.captureNameForId(capture.index) orelse continue;
        if (name[0] == '_' or isMeta(name)) continue;
        if (!predicatesHold(query, match, source)) continue;
        const start = capture.node.startByte();
        const end = capture.node.endByte();
        if (end > start) try spans.append(allocator, .{ .start = start, .end = end, .pattern = match.pattern_index, .name = name });
    }
    std.mem.sort(Span, spans.items, {}, Span.lessThan);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try render(allocator, &out, source, spans.items);
    return try out.toOwnedSlice(allocator);
}

fn find(lang: []const u8) ?usize {
    for (grammars, 0..) |g, i| {
        for (g.names) |n| if (std.ascii.eqlIgnoreCase(n, lang)) return i;
    }
    return null;
}

fn getQuery(index: usize, language: *const ts.Language) !*ts.Query {
    if (queries[index].load(.acquire)) |q| return q;
    var error_offset: u32 = 0;
    const query = try ts.Query.create(language, grammars[index].highlights, &error_offset);
    disableRegexPatterns(query);
    if (queries[index].cmpxchgStrong(null, query, .acq_rel, .acquire)) |winner| {
        query.destroy();
        return winner.?;
    }
    return query;
}

fn isMeta(name: []const u8) bool {
    for ([_][]const u8{ "spell", "nospell", "none", "conceal" }) |m| if (std.mem.eql(u8, name, m)) return true;
    return false;
}

const Span = struct {
    start: u32,
    end: u32,
    pattern: u32,
    name: []const u8,

    fn lessThan(_: void, a: Span, b: Span) bool {
        if (a.start != b.start) return a.start < b.start;
        if (a.end != b.end) return a.end > b.end;
        return a.pattern > b.pattern;
    }
};

fn render(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source: []const u8, spans: []const Span) !void {
    var open: [32]u32 = undefined;
    var depth: usize = 0;
    var pos: u32 = 0;
    var last: ?Span = null;

    for (spans) |span| {
        while (depth > 0 and open[depth - 1] <= span.start) {
            depth -= 1;
            try close(allocator, out, source, &pos, open[depth]);
        }
        if (last) |l| if (l.start == span.start and l.end == span.end) continue;
        if (span.start < pos or depth == open.len or (depth > 0 and span.end > open[depth - 1])) continue;

        try escape(allocator, out, source[pos..span.start]);
        pos = span.start;
        try out.appendSlice(allocator, "<span class=\"");
        var i: usize = 0;
        while (i <= span.name.len) : (i += 1) {
            if (i < span.name.len and span.name[i] != '.') continue;
            if (out.getLast() != '"') try out.append(allocator, ' ');
            try out.appendSlice(allocator, "hl-");
            for (span.name[0..i]) |c| try out.append(allocator, if (c == '.') '-' else c);
        }
        try out.appendSlice(allocator, "\">");
        open[depth] = span.end;
        depth += 1;
        last = span;
    }
    while (depth > 0) {
        depth -= 1;
        try close(allocator, out, source, &pos, open[depth]);
    }
    try escape(allocator, out, source[pos..]);
}

fn close(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source: []const u8, pos: *u32, end: u32) !void {
    try escape(allocator, out, source[pos.*..end]);
    pos.* = end;
    try out.appendSlice(allocator, "</span>");
}

fn escape(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| switch (c) {
        '<' => try out.appendSlice(allocator, "&lt;"),
        '>' => try out.appendSlice(allocator, "&gt;"),
        '&' => try out.appendSlice(allocator, "&amp;"),
        '"' => try out.appendSlice(allocator, "&quot;"),
        else => try out.append(allocator, c),
    };
}

// Tree-sitter leaves text predicates to the host: exact-text ones are checked
// below, and patterns needing a regex (`#match?`) are disabled.
fn disableRegexPatterns(query: *ts.Query) void {
    for (0..query.patternCount()) |i| {
        const pattern: u32 = @intCast(i);
        for (query.predicatesForPattern(pattern)) |step| {
            const op = if (step.type == .string) query.stringValueForId(step.value_id) orelse "" else "";
            if (std.mem.endsWith(u8, op, "match?")) {
                query.disablePattern(pattern);
                break;
            }
        }
    }
}

fn predicatesHold(query: *const ts.Query, match: ts.Query.Match, source: []const u8) bool {
    const steps = query.predicatesForPattern(match.pattern_index);
    var start: usize = 0;
    for (steps, 0..) |step, i| {
        if (step.type != .done) continue;
        if (!predicateHolds(query, match, source, steps[start..i])) return false;
        start = i + 1;
    }
    return true;
}

fn predicateHolds(query: *const ts.Query, match: ts.Query.Match, source: []const u8, steps: []const ts.Query.PredicateStep) bool {
    if (steps.len < 3 or steps[0].type != .string or steps[1].type != .capture) return true;
    const op = query.stringValueForId(steps[0].value_id) orelse return true;
    const negate = std.mem.startsWith(u8, op, "not-");
    const name = if (negate) op[4..] else op;
    if (!std.mem.eql(u8, name, "eq?") and !std.mem.eql(u8, name, "any-of?")) return true;

    const text = captureText(match, source, steps[1].value_id) orelse return true;
    for (steps[2..]) |arg| {
        const value = switch (arg.type) {
            .string => query.stringValueForId(arg.value_id),
            .capture => captureText(match, source, arg.value_id),
            .done => null,
        } orelse continue;
        if (std.mem.eql(u8, text, value)) return !negate;
    }
    return negate;
}

fn captureText(match: ts.Query.Match, source: []const u8, capture: u32) ?[]const u8 {
    for (match.captures) |c| {
        if (c.index == capture) return source[c.node.startByte()..c.node.endByte()];
    }
    return null;
}

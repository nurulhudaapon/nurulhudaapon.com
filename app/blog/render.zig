const markz = @import("markz");
const highlighter = @import("highlight");
const std = @import("std");

const Document = markz.Document;
const Node = markz.Node;
const SourceSpan = markz.SourceSpan;

pub fn html(allocator: std.mem.Allocator, markdown: []const u8) ![]const u8 {
    if (markdown.len == 0) return error.EmptySource;

    var doc = try markz.parseWith(allocator, markdown, .{ .gfm = true });
    defer doc.deinit();

    try transform(&doc, doc.root);
    return try markz.renderHtml(allocator, &doc);
}

// Rewrites the blog's markdown extensions that CommonMark leaves as plain text:
// `![](url align="center")` images and `%[https://youtu.be/…]` embeds.
fn transform(doc: *Document, parent: *Node) !void {
    var child = parent.first_child;
    while (child) |node| {
        const next = node.next;
        try transform(doc, node);

        switch (node.tag) {
            .paragraph => try paragraph(doc, node),
            .heading => try rewriteTexts(doc, node),
            .code_block => try highlight(doc, node),
            else => {},
        }

        child = next;
    }
}

fn highlight(doc: *Document, node: *Node) !void {
    const allocator = doc.arena.allocator();
    const lang = std.mem.sliceTo(doc.getCodeBlockData(node.data.code_block).info, ' ');
    const code = if (node.first_child) |c| doc.nodeText(c) else "";
    const body = try highlighter.html(allocator, lang, code) orelse return;
    const block_html = try allocator.print("<pre><code class=\"language-{s} hl\">{s}\n</code></pre>", .{ lang, body });
    replace(node, try doc.createNode(.html_block, .{ .literal = block_html }, SourceSpan.empty));
}

fn paragraph(doc: *Document, para: *Node) !void {
    if (para.first_child) |only| {
        if (only == para.last_child and only.tag == .text) {
            const trimmed = std.mem.trim(u8, doc.nodeText(only), " \t\r\n");
            if (wholeEmbed(trimmed)) |url| {
                if (try youtube(doc, url, .block)) |embed| {
                    return replace(para, try doc.createNode(.html_block, .{ .literal = embed }, SourceSpan.empty));
                }
            }
        }
    }
    try rewriteTexts(doc, para);
}

fn replace(node: *Node, with: *Node) void {
    node.insertAfter(with);
    node.detach();
}

fn rewriteTexts(doc: *Document, parent: *Node) !void {
    var child = parent.first_child;
    while (child) |node| {
        const next = node.next;
        if (node.tag == .text) try rewriteText(doc, node);
        child = next;
    }
}

fn rewriteText(doc: *Document, text_node: *Node) !void {
    const text = doc.nodeText(text_node);
    if (std.mem.indexOf(u8, text, "%[") == null and std.mem.indexOf(u8, text, "![") == null) return;

    var pieces: std.ArrayList(*Node) = .empty;
    defer pieces.deinit(doc.arena.allocator());

    var i: usize = 0;
    while (i < text.len) {
        const embed_at = std.mem.indexOfPos(u8, text, i, "%[");
        const image_at = std.mem.indexOfPos(u8, text, i, "![");

        const next_special: ?struct { at: usize, kind: enum { embed, image } } = blk: {
            if (embed_at == null and image_at == null) break :blk null;
            if (embed_at) |e| {
                if (image_at) |im| {
                    break :blk if (e <= im) .{ .at = e, .kind = .embed } else .{ .at = im, .kind = .image };
                }
                break :blk .{ .at = e, .kind = .embed };
            }
            break :blk .{ .at = image_at.?, .kind = .image };
        };

        const special = next_special orelse {
            try pieces.append(doc.arena.allocator(), try makeText(doc, text[i..]));
            break;
        };

        if (special.at > i) {
            try pieces.append(doc.arena.allocator(), try makeText(doc, text[i..special.at]));
        }

        const parsed = switch (special.kind) {
            .embed => embedAt(text, special.at),
            .image => imageAt(text, special.at),
        };

        if (parsed) |p| {
            const replacement: *Node = switch (p.value) {
                .embed => |url| blk: {
                    if (try youtube(doc, url, .span)) |embed| {
                        break :blk try doc.createNode(.html_inline, .{ .literal = embed }, SourceSpan.empty);
                    }
                    break :blk try makeText(doc, text[special.at..p.end]);
                },
                .image => |img| blk: {
                    const dest = try doc.allocString(img.destination);
                    const idx = try doc.storeLinkData(.{
                        .destination = dest,
                        .title = "",
                    });
                    const image = try doc.createNode(.image, .{ .image = idx }, SourceSpan.empty);
                    if (img.alt.len > 0) {
                        image.appendChild(try makeText(doc, img.alt));
                    }
                    break :blk image;
                },
            };
            try pieces.append(doc.arena.allocator(), replacement);
            i = p.end;
        } else {
            try pieces.append(doc.arena.allocator(), try makeText(doc, text[special.at .. special.at + 1]));
            i = special.at + 1;
        }
    }

    var cursor: *Node = text_node;
    for (pieces.items) |piece| {
        cursor.insertAfter(piece);
        cursor = piece;
    }
    text_node.detach();
}

const Special = struct {
    value: union(enum) {
        embed: []const u8,
        image: struct { alt: []const u8, destination: []const u8 },
    },
    end: usize,
};

fn wholeEmbed(text: []const u8) ?[]const u8 {
    const parsed = embedAt(text, 0) orelse return null;
    if (parsed.end != text.len) return null;
    return parsed.value.embed;
}

fn embedAt(text: []const u8, at: usize) ?Special {
    if (at + 2 > text.len or text[at] != '%' or text[at + 1] != '[') return null;
    const close = std.mem.indexOfScalarPos(u8, text, at + 2, ']') orelse return null;
    const url = std.mem.trim(u8, text[at + 2 .. close], " \t\r\n");
    if (url.len == 0) return null;
    return .{ .value = .{ .embed = url }, .end = close + 1 };
}

// `![alt](url align="center")`: CommonMark rejects the attributes, so the image is left as text.
fn imageAt(text: []const u8, at: usize) ?Special {
    if (at + 2 > text.len or text[at] != '!' or text[at + 1] != '[') return null;
    const alt_end = std.mem.indexOfScalarPos(u8, text, at + 2, ']') orelse return null;
    if (alt_end + 1 >= text.len or text[alt_end + 1] != '(') return null;

    const dest_start = alt_end + 2;
    const dest_end = std.mem.indexOfScalarPos(u8, text, dest_start, ')') orelse return null;
    const raw_dest = text[dest_start..dest_end];
    const destination = stripAttrs(raw_dest);
    if (destination.len == 0) return null;

    if (std.mem.eql(u8, raw_dest, destination)) return null;

    return .{
        .value = .{
            .image = .{
                .alt = text[at + 2 .. alt_end],
                .destination = destination,
            },
        },
        .end = dest_end + 1,
    };
}

fn stripAttrs(dest: []const u8) []const u8 {
    var cut = dest.len;
    if (std.mem.indexOf(u8, dest, " align=")) |idx| cut = @min(cut, idx);
    return std.mem.trimEnd(u8, dest[0..cut], " \t");
}

fn makeText(doc: *Document, text: []const u8) !*Node {
    const duped = try doc.allocString(text);
    return try doc.createNode(.text, .{ .literal = duped }, SourceSpan.empty);
}

fn youtube(doc: *Document, url: []const u8, comptime placement: enum { block, span }) !?[]const u8 {
    const id = videoId(url) orelse return null;
    const iframe_attrs =
        \\src="https://www.youtube.com/embed/{s}" title="YouTube video" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen loading="lazy"></iframe>
    ;
    const fmt = switch (placement) {
        .block => "<div class=\"video-embed\"><iframe " ++ iframe_attrs ++ "</div>",
        .span => "<iframe class=\"video-embed\" " ++ iframe_attrs,
    };
    return try doc.arena.allocator().print(fmt, .{id});
}

fn videoId(url: []const u8) ?[]const u8 {
    const prefixes = [_][]const u8{
        "https://youtu.be/",
        "http://youtu.be/",
        "https://www.youtube.com/embed/",
        "http://www.youtube.com/embed/",
        "https://youtube.com/embed/",
        "http://youtube.com/embed/",
    };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, url, prefix)) {
            const rest = url[prefix.len..];
            const end = std.mem.indexOfAny(u8, rest, "?&#") orelse rest.len;
            if (end == 0) return null;
            return rest[0..end];
        }
    }

    const watch_hosts = [_][]const u8{
        "https://www.youtube.com/watch?",
        "http://www.youtube.com/watch?",
        "https://youtube.com/watch?",
        "http://youtube.com/watch?",
        "https://m.youtube.com/watch?",
        "http://m.youtube.com/watch?",
    };
    for (watch_hosts) |host| {
        if (!std.mem.startsWith(u8, url, host)) continue;
        var params = std.mem.splitScalar(u8, url[host.len..], '&');
        while (params.next()) |param| {
            if (std.mem.startsWith(u8, param, "v=")) {
                const id = param["v=".len..];
                if (id.len == 0) return null;
                return id;
            }
        }
    }
    return null;
}

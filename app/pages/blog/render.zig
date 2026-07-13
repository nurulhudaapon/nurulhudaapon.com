const markz = @import("markz");
const std = @import("std");
const hashnode = @import("hashnode.zig");

const Document = markz.Document;
const Node = markz.Node;
const SourceSpan = markz.SourceSpan;

pub fn renderMarkdown(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    if (source.len == 0) return error.EmptySource;

    var doc = try markz.parseWith(allocator, source, .{ .gfm = true });
    defer doc.deinit();

    try transformHashnodeAst(&doc);
    try localizeImageUrls(&doc);
    return try markz.renderHtml(allocator, &doc);
}

/// Point image (and image-like link) destinations at `/images/hn/...`.
fn localizeImageUrls(doc: *Document) !void {
    var iter = doc.iterator();
    while (iter.next()) |event| {
        switch (event) {
            .enter => |node| switch (node.tag) {
                .image => {
                    const idx = node.data.image;
                    const dest = doc.getLinkData(idx).destination;
                    if (try hashnode.localizeUrl(doc.arena.allocator(), dest)) |local| {
                        doc.link_data.items[idx].destination = local;
                    }
                },
                .link => {
                    const idx = node.data.link;
                    const dest = doc.getLinkData(idx).destination;
                    if (try hashnode.localizeUrl(doc.arena.allocator(), dest)) |local| {
                        doc.link_data.items[idx].destination = local;
                    }
                },
                else => {},
            },
            else => {},
        }
    }
}

/// Rewrite Hashnode-specific syntax that CommonMark leaves as plain text:
/// - `![](url align="center")` → image nodes
/// - `%[https://youtu.be/…]` → YouTube embed HTML
fn transformHashnodeAst(doc: *Document) !void {
    try transformChildren(doc, doc.root);
}

fn transformChildren(doc: *Document, parent: *Node) !void {
    var child = parent.first_child;
    while (child) |node| {
        const next = node.next;
        try transformChildren(doc, node);

        switch (node.tag) {
            .paragraph => try transformParagraph(doc, node),
            // Images/embeds can also appear in headings.
            .heading => {
                var inline_child = node.first_child;
                while (inline_child) |n| {
                    const nnext = n.next;
                    if (n.tag == .text) try rewriteTextNode(doc, n);
                    inline_child = nnext;
                }
            },
            else => {},
        }

        child = next;
    }
}

fn transformParagraph(doc: *Document, para: *Node) !void {
    if (para.first_child != null and para.first_child == para.last_child) {
        const only = para.first_child.?;
        if (only.tag == .text) {
            const trimmed = std.mem.trim(u8, doc.nodeText(only), " \t\r\n");
            if (parsePercentEmbed(trimmed)) |url| {
                if (try youtubeEmbedHtml(doc, url)) |html| {
                    const block = try doc.createNode(.html_block, .{ .literal = html }, SourceSpan.empty);
                    para.insertAfter(block);
                    para.detach();
                    return;
                }
            }
        }
    }

    var child = para.first_child;
    while (child) |node| {
        const next = node.next;
        if (node.tag == .text) try rewriteTextNode(doc, node);
        child = next;
    }
}

fn rewriteTextNode(doc: *Document, text_node: *Node) !void {
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
            .embed => parsePercentEmbedAt(text, special.at),
            .image => parseBrokenImageAt(text, special.at),
        };

        if (parsed) |p| {
            const replacement: *Node = switch (p.value) {
                .embed => |url| blk: {
                    if (try youtubeEmbedHtmlInline(doc, url)) |html| {
                        break :blk try doc.createNode(.html_inline, .{ .literal = html }, SourceSpan.empty);
                    }
                    break :blk try makeText(doc, text[special.at..p.end]);
                },
                .image => |img| blk: {
                    const dest = (try hashnode.localizeUrl(doc.arena.allocator(), img.destination)) orelse
                        try doc.allocString(img.destination);
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

const ParsedSpecial = union(enum) {
    embed: []const u8,
    image: struct { alt: []const u8, destination: []const u8 },
};

const ParsedAt = struct {
    value: ParsedSpecial,
    end: usize,
};

fn parsePercentEmbed(text: []const u8) ?[]const u8 {
    const parsed = parsePercentEmbedAt(text, 0) orelse return null;
    if (parsed.end != text.len) return null;
    return switch (parsed.value) {
        .embed => |url| url,
        else => null,
    };
}

fn parsePercentEmbedAt(text: []const u8, at: usize) ?ParsedAt {
    if (at + 2 > text.len or text[at] != '%' or text[at + 1] != '[') return null;
    const close = std.mem.indexOfScalarPos(u8, text, at + 2, ']') orelse return null;
    const url = std.mem.trim(u8, text[at + 2 .. close], " \t\r\n");
    if (url.len == 0) return null;
    return .{ .value = .{ .embed = url }, .end = close + 1 };
}

fn parseBrokenImageAt(text: []const u8, at: usize) ?ParsedAt {
    if (at + 2 > text.len or text[at] != '!' or text[at + 1] != '[') return null;
    const alt_end = std.mem.indexOfScalarPos(u8, text, at + 2, ']') orelse return null;
    if (alt_end + 1 >= text.len or text[alt_end + 1] != '(') return null;

    const dest_start = alt_end + 2;
    const dest_end = std.mem.indexOfScalarPos(u8, text, dest_start, ')') orelse return null;
    const raw_dest = text[dest_start..dest_end];
    const destination = stripInlineHtmlAttrs(raw_dest);
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

fn stripInlineHtmlAttrs(dest: []const u8) []const u8 {
    var cut = dest.len;
    if (std.mem.indexOf(u8, dest, " align=")) |idx| cut = @min(cut, idx);
    return std.mem.trimEnd(u8, dest[0..cut], " \t");
}

fn makeText(doc: *Document, text: []const u8) !*Node {
    const duped = try doc.allocString(text);
    return try doc.createNode(.text, .{ .literal = duped }, SourceSpan.empty);
}

fn youtubeEmbedHtml(doc: *Document, url: []const u8) !?[]const u8 {
    const id = youtubeVideoId(url) orelse return null;
    return try std.fmt.allocPrint(
        doc.arena.allocator(),
        \\<div class="video-embed"><iframe src="https://www.youtube.com/embed/{s}" title="YouTube video" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen loading="lazy"></iframe></div>
    ,
        .{id},
    );
}

fn youtubeEmbedHtmlInline(doc: *Document, url: []const u8) !?[]const u8 {
    const id = youtubeVideoId(url) orelse return null;
    return try std.fmt.allocPrint(
        doc.arena.allocator(),
        \\<iframe class="video-embed" src="https://www.youtube.com/embed/{s}" title="YouTube video" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen loading="lazy"></iframe>
    ,
        .{id},
    );
}

fn youtubeVideoId(url: []const u8) ?[]const u8 {
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

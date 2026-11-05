const std = @import("std");
const zx = @import("zx");
const lunasvg = @import("lunasvg");

const url = "https://avatars.githubusercontent.com/nurulhudaapon?s=512";
const color_key = "github-avatar";
const gray_key = "github-avatar-gray";

pub fn fetch(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const kv = zx.kv.scoped(.avatar);
    if (try kv.get(arena, color_key)) |cached| return cached;

    var client: zx.http.Client = .{ .io = io, .allocator = arena };
    defer client.deinit();
    const response = try client.fetch(.{
        .url = url,
        .headers = &.{
            .{ .name = "User-Agent", .value = "nurulhudaapon.com" },
            .{ .name = "Accept", .value = "image/*" },
        },
        .timeout = .{ .duration = .{ .raw = .fromMilliseconds(15_000), .clock = .awake } },
    });
    defer response.deinit(arena);
    if (response.status.class() != .success) {
        zx.log.warn("avatar: fetch failed status={d}", .{@backingInt(response.status)});
        return error.NetworkError;
    }

    try kv.put(color_key, response.body, .{});
    return try arena.dupe(u8, response.body);
}

// Falls back to the color image when it can't be desaturated.
pub fn gray(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const kv = zx.kv.scoped(.avatar);
    if (try kv.get(arena, gray_key)) |cached| return cached;

    const color = try fetch(arena, io);
    const out = grayscale(arena, color) catch |err| {
        zx.log.warn("avatar: grayscale failed ({s}), using color", .{@errorName(err)});
        return color;
    };
    try kv.put(gray_key, out, .{});
    return out;
}

pub fn dataUri(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    const bytes = try gray(arena, io);
    return encodeDataUri(arena, mime(bytes) orelse .png, bytes);
}

pub fn contentType(bytes: []const u8) zx.server.Response.ContentType {
    return switch (mime(bytes) orelse .png) {
        .png => .@"image/png",
        .jpeg => .@"image/jpeg",
        .webp => .@"image/webp",
    };
}

const Mime = enum {
    png,
    jpeg,
    webp,

    fn name(m: Mime) []const u8 {
        return switch (m) {
            .png => "image/png",
            .jpeg => "image/jpeg",
            .webp => "image/webp",
        };
    }
};

fn mime(bytes: []const u8) ?Mime {
    if (std.mem.startsWith(u8, bytes, "\x89PNG")) return .png;
    if (std.mem.startsWith(u8, bytes, "\xff\xd8\xff")) return .jpeg;
    if (std.mem.startsWith(u8, bytes, "RIFF")) return .webp;
    return null;
}

fn encodeDataUri(allocator: std.mem.Allocator, m: Mime, bytes: []const u8) ![]u8 {
    const Encoder = std.base64.standard.Encoder;
    const prefix = try allocator.print("data:{s};base64,", .{m.name()});
    defer allocator.free(prefix);
    const out = try allocator.alloc(u8, prefix.len + Encoder.calcSize(bytes.len));
    @memcpy(out[0..prefix.len], prefix);
    _ = Encoder.encode(out[prefix.len..], bytes);
    return out;
}

fn grayscale(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const href = try encodeDataUri(allocator, mime(bytes) orelse return error.UnsupportedImage, bytes);
    defer allocator.free(href);

    const svg = try allocator.print(
        \\<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="512" height="512">
        \\<image href="{s}" xlink:href="{s}" width="512" height="512" preserveAspectRatio="xMidYMid slice"/>
        \\</svg>
    , .{ href, href });
    defer allocator.free(svg);

    const doc = try lunasvg.Document.loadFromData(svg);
    defer doc.deinit();

    var bitmap = try doc.renderToBitmap(.{ .width = 512, .height = 512, .background_color = 0x00000000 });
    defer bitmap.deinit();

    bitmap.convertToRGBA();
    const width: usize = @intCast(bitmap.width());
    const height: usize = @intCast(bitmap.height());
    const stride: usize = @intCast(bitmap.stride());
    const pixels = bitmap.data();
    for (0..height) |y| {
        const row = pixels[y * stride ..][0 .. width * 4];
        for (0..width) |x| {
            const px = row[x * 4 ..][0..3];
            const r: u32 = px[0];
            const g: u32 = px[1];
            const b: u32 = px[2];
            @memset(px, @intCast((r * 77 + g * 150 + b * 29) >> 8));
        }
    }

    return try bitmap.writeToPngAlloc(allocator);
}

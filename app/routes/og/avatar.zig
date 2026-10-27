const std = @import("std");
const zx = @import("zx");
const lunasvg = @import("lunasvg");

pub const github_user = "nurulhudaapon";
pub const github_avatar_url = "https://avatars.githubusercontent.com/" ++ github_user ++ "?s=512";
pub const cache_key = "github-avatar";
pub const gray_cache_key = "github-avatar-gray";

pub fn fetch(allocator: std.mem.Allocator) ![]const u8 {
    const avatar_kv = zx.kv.scoped(.avatar);

    if (try avatar_kv.get(allocator, cache_key)) |cached| {
        zx.log.debug("avatar: cache hit key={s} bytes={d}", .{ cache_key, cached.len });
        return cached;
    }

    zx.log.debug("avatar: fetching {s}", .{github_avatar_url});
    var response = (try zx.fetch(.blocking, allocator, github_avatar_url, .{
        .headers = &.{
            .{ .name = "User-Agent", .value = "nurulhudaapon.com" },
            .{ .name = "Accept", .value = "image/*" },
        },
        .timeout_ms = 15_000,
    })) orelse return error.NetworkError;
    defer response.deinit();
    if (!response.ok()) {
        zx.log.warn("avatar: fetch failed status={d} url={s}", .{ response.status, github_avatar_url });
        return error.NetworkError;
    }

    const body = try response.bytes();
    zx.log.debug("avatar: fetched bytes={d} status={d}", .{ body.len, response.status });
    try avatar_kv.put(cache_key, body, .{});
    return try allocator.dupe(u8, body);
}

pub fn fetchGrayscale(allocator: std.mem.Allocator) ![]const u8 {
    const avatar_kv = zx.kv.scoped(.avatar);

    if (try avatar_kv.get(allocator, gray_cache_key)) |cached| {
        zx.log.debug("avatar: gray cache hit bytes={d}", .{cached.len});
        return cached;
    }

    const color = try fetch(allocator);
    const gray = toGrayscalePng(allocator, color) catch |err| {
        zx.log.warn("avatar: grayscale failed ({s}), using color", .{@errorName(err)});
        return color;
    };
    zx.log.debug("avatar: grayscale ok bytes={d}", .{gray.len});
    try avatar_kv.put(gray_cache_key, gray, .{});
    return gray;
}

pub fn dataUri(allocator: std.mem.Allocator) ![]const u8 {
    const bytes = try fetchGrayscale(allocator);
    const mime: []const u8 = if (std.mem.startsWith(u8, bytes, "\x89PNG"))
        "image/png"
    else if (bytes.len >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff)
        "image/jpeg"
    else if (std.mem.startsWith(u8, bytes, "RIFF"))
        "image/webp"
    else
        "image/png";

    const Encoder = std.base64.standard.Encoder;
    const b64 = try allocator.alloc(u8, Encoder.calcSize(bytes.len));
    _ = Encoder.encode(b64, bytes);
    return try allocator.print("data:{s};base64,{s}", .{ mime, b64 });
}

pub fn contentType(bytes: []const u8) zx.server.Response.ContentType {
    if (std.mem.startsWith(u8, bytes, "\x89PNG")) return .@"image/png";
    if (bytes.len >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff) return .@"image/jpeg";
    if (std.mem.startsWith(u8, bytes, "RIFF")) return .@"image/webp";
    return .@"image/png";
}

fn toGrayscalePng(allocator: std.mem.Allocator, image_bytes: []const u8) ![]u8 {
    const mime: []const u8 = if (std.mem.startsWith(u8, image_bytes, "\x89PNG"))
        "image/png"
    else if (image_bytes.len >= 3 and image_bytes[0] == 0xff and image_bytes[1] == 0xd8 and image_bytes[2] == 0xff)
        "image/jpeg"
    else if (std.mem.startsWith(u8, image_bytes, "RIFF"))
        "image/webp"
    else
        return error.UnsupportedImage;

    const Encoder = std.base64.standard.Encoder;
    const b64 = try allocator.alloc(u8, Encoder.calcSize(image_bytes.len));
    defer allocator.free(b64);
    _ = Encoder.encode(b64, image_bytes);

    const href = try allocator.print("data:{s};base64,{s}", .{ mime, b64 });
    defer allocator.free(href);

    const svg = try allocator.print(
        \\<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="512" height="512">
        \\<image href="{s}" xlink:href="{s}" width="512" height="512" preserveAspectRatio="xMidYMid slice"/>
        \\</svg>
    , .{ href, href });
    defer allocator.free(svg);

    const doc = try lunasvg.Document.loadFromData(svg);
    defer doc.deinit();

    var bitmap = try doc.renderToBitmap(.{
        .width = 512,
        .height = 512,
        .background_color = 0x00000000,
    });
    defer bitmap.deinit();

    bitmap.convertToRGBA();
    desaturateRgba(bitmap.data(), @intCast(bitmap.width()), @intCast(bitmap.height()), @intCast(bitmap.stride()));

    return try bitmap.writeToPngAlloc(allocator);
}

fn desaturateRgba(pixels: []u8, width: usize, height: usize, stride: usize) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        const row = pixels[y * stride ..][0 .. width * 4];
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const i = x * 4;
            const r: u32 = row[i];
            const g: u32 = row[i + 1];
            const b: u32 = row[i + 2];
            const gray: u8 = @intCast((r * 77 + g * 150 + b * 29) >> 8);
            row[i] = gray;
            row[i + 1] = gray;
            row[i + 2] = gray;
        }
    }
}

pub fn GET(ctx: zx.RouteContext) !void {
    const image_path = ctx.request.pathname;
    const image_data = try getImageData(ctx.arena, image_path);

    ctx.response.text(image_data);
    ctx.response.setContentType(contentTypeForPath(image_path));
    ctx.response.headers.add("Cache-Control", "public, max-age=31536000, immutable");
}

fn getImageData(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, path, hashnode.local_prefix)) {
        const hashnode_kv = zx.kv.scoped(.hashnode);
        const hashnode_image_path = path[hashnode.local_prefix.len..];
        const hashnode_image_url = try std.fmt.allocPrint(allocator, "{s}{s}", .{
            hashnode.cdn_prefix,
            hashnode_image_path,
        });

        if (try hashnode_kv.get(allocator, hashnode_image_path)) |image_data| {
            zx.log.debug("getImageData: hashnode_image_path={s} found in cache", .{hashnode_image_path});
            return image_data;
        }

        zx.log.debug("getImageData: hashnode_image_url={s}", .{hashnode_image_url});
        var response = (try zx.fetch(.blocking, allocator, hashnode_image_url, .{
            .headers = &.{},
            .timeout_ms = 120_000,
        })) orelse return error.NetworkError;
        defer response.deinit();
        if (!response.ok()) {
            return error.NetworkError;
        }
        const body = try response.bytes();
        try hashnode_kv.put(hashnode_image_path, body, .{});
        return try allocator.dupe(u8, body);
    }
    return error.InvalidPath;
}

fn contentTypeForPath(path: []const u8) zx.server.Response.ContentType {
    if (std.ascii.endsWithIgnoreCase(path, ".png")) return .@"image/png";
    if (std.ascii.endsWithIgnoreCase(path, ".jpg") or std.ascii.endsWithIgnoreCase(path, ".jpeg")) return .@"image/jpeg";
    if (std.ascii.endsWithIgnoreCase(path, ".webp")) return .@"image/webp";
    if (std.ascii.endsWithIgnoreCase(path, ".gif")) return .@"image/gif";
    if (std.ascii.endsWithIgnoreCase(path, ".svg")) return .@"image/svg+xml";
    if (std.ascii.endsWithIgnoreCase(path, ".avif")) return .@"image/avif";
    return .@"application/octet-stream";
}

fn staticParams(ctx: *zx.StaticContext) !void {
    const images = try posts.collectHashnodeImageParams(ctx.arena);
    for (images) |image| {
        try ctx.params.add(.{ .@"*" = image });
    }
}

pub const options = zx.RouteOptions{
    .static = staticParams,
};

const zx = @import("zx");
const std = @import("std");
const posts = @import("../../../pages/blog/posts.zig");
const hashnode = @import("../../../pages/blog/hashnode.zig");

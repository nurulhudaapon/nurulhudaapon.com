pub fn GET(ctx: zx.RouteContext) !void {
    const image_path = ctx.request.pathname;
    const image_data = try getImageData(ctx.arena, image_path);

    ctx.response.text(image_data);
    ctx.response.setContentType(contentTypeForPath(image_path));
    ctx.response.headers.add("Cache-Control", "public, max-age=31536000, immutable");
}

const local_prefix = "/blog/images/";

fn getImageData(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const relative = stripLocalPrefix(path) orelse return error.InvalidPath;
    const file_path = try std.fmt.allocPrint(allocator, "images/{s}", .{relative});
    defer allocator.free(file_path);

    zx.log.debug("blog.images: path={s} file={s}", .{ path, file_path });
    return git.readRepoFile(allocator, file_path) catch |err| switch (err) {
        error.FileNotFound, error.RepositoryNotFound => {
            zx.log.warn("blog.images: missing file={s}", .{file_path});
            return error.NotFound;
        },
        else => {
            zx.log.warn("blog.images: failed file={s} err={any}", .{ file_path, err });
            return err;
        },
    };
}

fn stripLocalPrefix(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, local_prefix)) return null;
    const rest = path[local_prefix.len..];
    return if (rest.len > 0) rest else null;
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
    const images = try posts.collectBlogImageParams(ctx.arena);
    for (images) |image| {
        try ctx.params.add(.{ .@"*" = image });
    }
}

pub const options = zx.RouteOptions{
    .static = staticParams,
};

const zx = @import("zx");
const std = @import("std");
const posts = @import("../../posts.zig");
const git = @import("../../git.zig");

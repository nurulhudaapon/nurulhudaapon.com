pub fn GET(ctx: zx.RouteContext) !void {
    const path = ctx.request.pathname;
    ctx.response.text(try read(ctx.arena, ctx.io, path));
    ctx.response.setContentType(contentType(path));
    ctx.response.headers.append("Cache-Control", "public, max-age=31536000, immutable");
}

const prefix = "/blog/images/";

fn read(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, path, prefix) or path.len == prefix.len) return error.InvalidPath;
    const file = try arena.print("images/{s}", .{path[prefix.len..]});

    zx.log.debug("blog.images: path={s} file={s}", .{ path, file });
    return git.blogs.readFile(arena, io, file) catch |err| switch (err) {
        error.FileNotFound, error.RepositoryNotFound => {
            zx.log.warn("blog.images: missing file={s}", .{file});
            return error.NotFound;
        },
        else => {
            zx.log.warn("blog.images: failed file={s} err={any}", .{ file, err });
            return err;
        },
    };
}

fn contentType(path: []const u8) zx.server.Response.ContentType {
    const types = [_]struct { []const u8, zx.server.Response.ContentType }{
        .{ ".png", .@"image/png" },
        .{ ".jpg", .@"image/jpeg" },
        .{ ".jpeg", .@"image/jpeg" },
        .{ ".webp", .@"image/webp" },
        .{ ".gif", .@"image/gif" },
        .{ ".svg", .@"image/svg+xml" },
        .{ ".avif", .@"image/avif" },
    };
    for (types) |entry| {
        if (std.ascii.endsWithIgnoreCase(path, entry[0])) return entry[1];
    }
    return .@"application/octet-stream";
}

fn staticParams(ctx: *zx.StaticContext) !void {
    for (try posts.imagePaths(ctx.arena, ctx.io)) |image| {
        try ctx.params.add(.{ .@"*" = image });
    }
}

pub const options = zx.RouteOptions{
    .rendering = .prerendered,
    .static = staticParams,
};

const zx = @import("zx");
const std = @import("std");
const posts = @import("../../../../blog.zig").posts;
const git = @import("../../../../blog.zig").git;

const std = @import("std");
const zx = @import("zx");
const store = @import("../store.zig");

pub fn handle(ctx: zx.RouteContext) !void {
    const q = ctx.request.query;
    const response_type = q.get("response_type") orelse "";
    const client_id = q.get("client_id") orelse "";
    const redirect_uri = q.get("redirect_uri") orelse "";
    if (!std.mem.eql(u8, response_type, "code") or client_id.len == 0 or redirect_uri.len == 0) {
        ctx.response.setStatus(.bad_request);
        return ctx.response.text("invalid_request: response_type=code, client_id, and redirect_uri are required");
    }

    const allowed = store.clientAllowsRedirect(ctx.arena, client_id, redirect_uri) catch false;
    if (!allowed) {
        ctx.response.setStatus(.bad_request);
        return ctx.response.text("invalid_request: unknown client_id or redirect_uri not registered");
    }

    var aw: std.Io.Writer.Allocating = .init(ctx.arena);
    try aw.writer.writeAll("/admin/mcp?");
    var first = true;
    inline for (.{
        "response_type",
        "client_id",
        "redirect_uri",
        "state",
        "code_challenge",
        "code_challenge_method",
        "scope",
        "resource",
    }) |key| {
        if (q.get(key)) |val| {
            if (!first) try aw.writer.writeAll("&");
            first = false;
            try aw.writer.writeAll(key);
            try aw.writer.writeAll("=");
            try appendQueryEscaped(&aw.writer, val);
        }
    }
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.redirect(aw.written(), .found);
}

fn appendQueryEscaped(w: *std.Io.Writer, value: []const u8) !void {
    for (value) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => try w.writeByte(c),
        ' ' => try w.writeAll("%20"),
        else => try w.print("%{X:0>2}", .{c}),
    };
}

pub fn GET(ctx: zx.RouteContext) !void {
    ctx.response.headers.append("Cache-Control", "private, no-store");
    ctx.response.headers.append("X-Robots-Tag", "noindex, nofollow");
    ctx.response.headers.append("Referrer-Policy", "no-referrer");

    const raw = ctx.request.params.get("token") orelse "";
    const token = if (std.mem.endsWith(u8, raw, ".ics")) raw[0 .. raw.len - ".ics".len] else raw;
    // Unknown and revoked tokens look the same, and say nothing about the feed.
    const link = (try calendars.findLink(ctx.arena, token)) orelse {
        ctx.response.setStatus(.not_found);
        return ctx.response.text("Not found");
    };

    const now = std.Io.Timestamp.now(zx.Io.default(), .real).toSeconds();
    const body = try calendars.renderFeed(ctx.arena, link.detail, now);
    calendars.touchLink(ctx.arena, link.id);

    ctx.response.text(body);
    ctx.response.headers.set("Content-Type", "text/calendar; charset=utf-8");
    ctx.response.headers.append("Content-Disposition", "inline; filename=\"calendar.ics\"");
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const calendars = @import("../../../pages/schedule/calendars.zig");

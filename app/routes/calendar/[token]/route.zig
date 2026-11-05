pub fn GET(ctx: zx.RouteContext) !void {
    ctx.response.headers.append("Cache-Control", "private, no-store");
    ctx.response.headers.append("X-Robots-Tag", "noindex, nofollow");
    ctx.response.headers.append("Referrer-Policy", "no-referrer");

    const raw = ctx.request.params.get("token") orelse "";
    const token = std.mem.cutSuffix(u8, raw, ".ics") orelse raw;
    // Unknown and revoked tokens look the same, and say nothing about the feed.
    const link = (try calendars.Link.find(ctx.arena, token)) orelse {
        ctx.response.setStatus(.not_found);
        return ctx.response.text("Not found");
    };

    const now = std.Io.Timestamp.now(ctx.io, .real).toSeconds();
    const rendered = try calendars.renderFeed(ctx.arena, link.detail, now);
    if (rendered.stale) _ = calendars.requestSync(ctx.arena, ctx.io, ctx.response, false);
    link.touch(ctx.arena, now);

    ctx.response.text(rendered.body);
    ctx.response.headers.set("Content-Type", "text/calendar; charset=utf-8");
    ctx.response.headers.append("Content-Disposition", "inline; filename=\"calendar.ics\"");
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const calendars = @import("../../../pages/schedule/calendars.zig");

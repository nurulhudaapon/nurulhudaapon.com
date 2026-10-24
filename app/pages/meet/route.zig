pub fn GET(ctx: zx.RouteContext) !void {
    const id = ctx.request.queries.get("id") orelse "";
    const target = try zx.db.row(ctx.arena, struct { url: ?[]const u8 },
        \\SELECT COALESCE(b.meet_url,
        \\  (SELECT val FROM credentials WHERE cat = 'caldav_meeting_url' LIMIT 1)) AS url
        \\FROM bookings b WHERE b.id = ?1 AND b.cancelled_at IS NULL
    , .{id});
    const url = (if (target) |t| t.url else null) orelse {
        ctx.response.setStatus(.not_found);
        return ctx.response.text("Meeting link not found.");
    };

    _ = zx.db.run(
        \\INSERT INTO meet_joins (booking_id, user_agent) VALUES (?1, ?2)
    , .{ id, ctx.request.headers.get("user-agent") orelse "" }) catch |err|
        zx.log.warn("meet: failed to record join for {s}: {any}", .{ id, err });

    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.redirect(url, 302);
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const zx = @import("zx");

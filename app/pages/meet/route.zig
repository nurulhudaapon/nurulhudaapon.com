pub fn GET(ctx: zx.RouteContext) !void {
    const id = ctx.request.queries.get("id") orelse "";
    const target = try zx.db.row(ctx.arena, struct { url: []const u8 },
        \\SELECT c.val AS url FROM bookings b, credentials c
        \\WHERE b.id = ?1 AND c.cat = 'caldav_meeting_url' LIMIT 1
    , .{id}) orelse {
        ctx.response.setStatus(.not_found);
        return ctx.response.text("Meeting link not found.");
    };

    _ = zx.db.run(
        \\INSERT INTO meet_joins (booking_id, user_agent) VALUES (?1, ?2)
    , .{ id, ctx.request.headers.get("user-agent") orelse "" }) catch |err|
        zx.log.warn("meet: failed to record join for {s}: {any}", .{ id, err });

    ctx.response.headers.add("Cache-Control", "no-store");
    ctx.response.redirect(target.url, 302);
}

const zx = @import("zx");

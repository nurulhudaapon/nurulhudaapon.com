const std = @import("std");
const builtin = @import("builtin");
const zx = @import("zx");
const slots = @import("slots.zig");
const caldav = @import("caldav.zig");
const ical = @import("ical.zig");
const settings = @import("settings.zig");

pub const Request = struct {
    name: []const u8,
    email: []const u8,
    notes: []const u8,
    honeypot: []const u8,
    origin: []const u8,
};

pub const Outcome = enum { booked, invalid, taken, failed };

const Booking = struct {
    id: []const u8,
    slot: slots.Interval,
    name: []const u8,
    email: []const u8,
    notes: []const u8,
};

const site_url = "https://nurulhudaapon.com";
const whitespace = " \t\r\n";

pub fn book(arena: std.mem.Allocator, start: i64, req: Request) Outcome {
    if (req.honeypot.len > 0) return .booked;

    const now = nowUnix();
    const rules = settings.load(arena);
    var b: Booking = .{
        .id = undefined,
        .slot = .{ .start = start, .end = start + rules.slotSeconds() },
        .name = std.mem.trim(u8, req.name, whitespace),
        .email = std.mem.trim(u8, req.email, whitespace),
        .notes = std.mem.trim(u8, req.notes, whitespace),
    };
    if (b.name.len == 0 or b.name.len > 100 or b.notes.len > 2000 or !isPlausibleEmail(b.email)) return .invalid;
    if (!slots.isBookable(rules, now, start)) return .invalid;

    const creds = (caldav.loadCredentials(arena) catch null) orelse return .failed;
    const busy = caldav.busy(arena, creds, slots.horizon(rules, now), false) catch return .failed;
    if (slots.isBusy(b.slot, busy)) return .taken;

    var random: [8]u8 = undefined;
    zx.io().random(&random);
    b.id = std.fmt.allocPrint(arena, "{d}-{x}", .{ now, random }) catch return .failed;

    switch (claim(arena, b)) {
        .claimed => {},
        .duplicate => return .booked,
        .taken => return .taken,
        .failed => return .failed,
    }
    createEvent(arena, creds, b, now, req.origin) catch |err| {
        zx.log.err("schedule: booking failed: {any}", .{err});
        _ = zx.db.run("DELETE FROM bookings WHERE id = ?1", .{b.id}) catch {};
        return .failed;
    };
    caldav.invalidateBusy();
    logInviteStatus(arena, creds, b.id);
    return .booked;
}

const Claim = enum { claimed, duplicate, taken, failed };

fn claim(arena: std.mem.Allocator, b: Booking) Claim {
    // The unique index on active starts_at serializes concurrent submissions. A
    // claim older than two minutes is stale: iCloud already reported the slot free.
    const result = zx.db.run(
        \\INSERT INTO bookings (id, starts_at, ends_at, name, email, notes, created_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, CAST(unixepoch() AS TEXT))
        \\ON CONFLICT (starts_at) WHERE cancelled_at IS NULL DO UPDATE SET
        \\  id = excluded.id, ends_at = excluded.ends_at, name = excluded.name,
        \\  email = excluded.email, notes = excluded.notes, created_at = excluded.created_at,
        \\  meet_url = NULL
        \\WHERE CAST(bookings.created_at AS INTEGER) < unixepoch() - 120
    , .{ b.id, b.slot.start, b.slot.end, b.name, b.email, b.notes }) catch |err| {
        zx.log.err("schedule: failed to claim slot: {any}", .{err});
        return .failed;
    };
    if (result.changes > 0) return .claimed;

    const holder = zx.db.row(arena, struct { email: []const u8 },
        \\SELECT email FROM bookings WHERE starts_at = ?1 AND cancelled_at IS NULL
    , .{b.slot.start}) catch null;
    if (holder) |h| if (std.ascii.eqlIgnoreCase(h.email, b.email)) return .duplicate;
    return .taken;
}

fn createEvent(arena: std.mem.Allocator, creds: caldav.Credentials, b: Booking, now: i64, origin_url: []const u8) !void {
    const meet_url = if (creds.meeting_url != null)
        try std.fmt.allocPrint(arena, "{s}/meet?id={s}", .{ origin_url, b.id })
    else
        null;
    const join = if (meet_url) |url| try std.fmt.allocPrint(arena, "Join: {s}\n\n", .{url}) else "";

    const ics = try ical.buildEvent(arena, .{
        .uid = try std.fmt.allocPrint(arena, "{s}@nurulhudaapon.com", .{b.id}),
        .start = b.slot.start,
        .end = b.slot.end,
        .now = now,
        .summary = try std.fmt.allocPrint(arena, "Meeting with {s}", .{b.name}),
        .description = try std.fmt.allocPrint(arena, "{s}Booked via nurulhudaapon.com/schedule\n\n{s} <{s}>\n\n{s}", .{ join, b.name, b.email, b.notes }),
        .organizer_email = creds.organizer_email,
        .organizer_name = "Nurul Huda (Apon)",
        .attendee_email = b.email,
        .attendee_name = b.name,
        .meeting_url = meet_url,
    });
    try caldav.putEvent(arena, creds, b.id, ics);
}

fn logInviteStatus(arena: std.mem.Allocator, creds: caldav.Credentials, id: []const u8) void {
    const stored = caldav.getEvent(arena, creds, id) catch |err| {
        zx.log.warn("schedule: couldn't read back booking: {any}", .{err});
        return;
    };
    const marker = "SCHEDULE-STATUS=";
    const at = std.mem.indexOf(u8, stored, marker) orelse {
        zx.log.warn("schedule: no SCHEDULE-STATUS, iCloud may not have sent an invitation", .{});
        return;
    };
    const status = stored[at + marker.len ..];
    zx.log.info("schedule: invitation SCHEDULE-STATUS={s}", .{status[0 .. std.mem.indexOfAny(u8, status, ";:\r\n") orelse status.len]});
}

pub fn origin(request: zx.server.Request) []const u8 {
    if (builtin.optimize != .debug) return site_url;
    const host = request.headers.get("host") orelse return site_url;
    return std.fmt.allocPrint(request.arena, "http://{s}", .{host}) catch site_url;
}

pub fn nowUnix() i64 {
    return std.Io.Timestamp.now(zx.io(), .real).toSeconds();
}

fn isPlausibleEmail(email: []const u8) bool {
    if (email.len > 200) return false;
    const at = std.mem.indexOfScalar(u8, email, '@') orelse return false;
    if (at == 0 or std.mem.indexOfScalarPos(u8, email, at + 1, '.') == null) return false;
    for (email) |ch| if (ch <= ' ' or std.mem.indexOfScalar(u8, "<>\",;:", ch) != null) return false;
    return true;
}

pub const Record = struct {
    id: []const u8,
    starts_at: i64,
    ends_at: i64,
    name: []const u8,
    email: []const u8,
    notes: ?[]const u8 = null,
    meet_url: ?[]const u8 = null,
    cancelled_at: ?[]const u8 = null,
    created_at: []const u8,
    joins: i64 = 0,
};

pub const Filter = enum { upcoming, past, cancelled };

const record_columns =
    \\SELECT b.id, b.starts_at, b.ends_at, b.name, b.email, b.notes, b.meet_url,
    \\  b.cancelled_at, b.created_at,
    \\  (SELECT COUNT(*) FROM meet_joins j WHERE j.booking_id = b.id) AS joins
    \\FROM bookings b
;

pub fn list(arena: std.mem.Allocator, filter: Filter, limit: i64) ![]const Record {
    const now = nowUnix();
    return switch (filter) {
        .upcoming => zx.db.rows(arena, Record, record_columns ++
            \\ WHERE b.cancelled_at IS NULL AND b.ends_at >= ?1 ORDER BY b.starts_at ASC LIMIT ?2
        , .{ now, limit }),
        .past => zx.db.rows(arena, Record, record_columns ++
            \\ WHERE b.cancelled_at IS NULL AND b.ends_at < ?1 ORDER BY b.starts_at DESC LIMIT ?2
        , .{ now, limit }),
        .cancelled => zx.db.rows(arena, Record, record_columns ++
            \\ WHERE b.cancelled_at IS NOT NULL ORDER BY b.starts_at DESC LIMIT ?1
        , .{limit}),
    };
}

pub const Counts = struct { upcoming: i64 = 0, past: i64 = 0, cancelled: i64 = 0 };

pub fn counts(arena: std.mem.Allocator) Counts {
    const row = zx.db.row(arena, Counts,
        \\SELECT COALESCE(SUM(cancelled_at IS NULL AND ends_at >= ?1), 0) AS upcoming,
        \\  COALESCE(SUM(cancelled_at IS NULL AND ends_at < ?1), 0) AS past,
        \\  COALESCE(SUM(cancelled_at IS NOT NULL), 0) AS cancelled
        \\FROM bookings
    , .{nowUnix()}) catch return .{};
    return row orelse .{};
}

/// Invites link to `/meet?id=…`, so changing this needs no new invitation.
pub fn setMeetUrl(id: []const u8, url: []const u8) !void {
    if (url.len > 0 and !settings.isHttpUrl(url)) return error.InvalidUrl;
    const result = try zx.db.run(
        \\UPDATE bookings SET meet_url = NULLIF(?1, '') WHERE id = ?2 AND cancelled_at IS NULL
    , .{ url, id });
    if (result.changes == 0) return error.NotFound;
}

pub fn cancel(arena: std.mem.Allocator, id: []const u8) !void {
    const creds = (try caldav.loadCredentials(arena)) orelse return error.NotConfigured;
    caldav.deleteEvent(arena, creds, id) catch |err| switch (err) {
        error.NotFound => zx.log.warn("schedule: event {s} already gone from calendar", .{id}),
        else => return err,
    };
    _ = try zx.db.run(
        \\UPDATE bookings SET cancelled_at = CAST(unixepoch() AS TEXT) WHERE id = ?1 AND cancelled_at IS NULL
    , .{id});
    caldav.invalidateBusy();
}

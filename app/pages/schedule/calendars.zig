const std = @import("std");
const zx = @import("zx");
const slots = @import("slots.zig");
const ical = @import("ical.zig");
const caldav = @import("caldav.zig");
const settings = @import("settings.zig");
const week = @import("week.zig");
const feed = @import("feed.zig");

const Interval = slots.Interval;

pub const Kind = enum { icloud, ics };

pub const Source = struct {
    id: i64,
    kind: Kind,
    name: []const u8,
    url: []const u8,
    color: []const u8,
    visible: bool,
    blocks_booking: bool,
    in_feed: bool,
    synced_at: ?[]const u8,

    // Host only: feed links often carry a private token in the path.
    pub fn host(self: Source) []const u8 {
        const scheme = std.mem.indexOf(u8, self.url, "://") orelse return self.url;
        const rest = self.url[scheme + 3 ..];
        return rest[0 .. std.mem.indexOfScalar(u8, rest, '/') orelse rest.len];
    }
};

pub const palette = [_][]const u8{ "#2563eb", "#16a34a", "#f6821f", "#db2777", "#7c3aed", "#0891b2", "#ca8a04", "#dc2626" };

const Row = struct {
    id: i64,
    kind: []const u8,
    name: []const u8,
    url: []const u8,
    color: []const u8,
    visible: i64,
    blocks_booking: i64,
    in_feed: i64,
    synced_at: ?[]const u8,
};

const select_cols = "SELECT id, kind, name, url, color, visible, blocks_booking, in_feed, synced_at FROM calendars";

pub fn list(arena: std.mem.Allocator) ![]const Source {
    const rows = try zx.db.rows(arena, Row, select_cols ++ " ORDER BY kind, name COLLATE NOCASE, id", .{});
    const out = try arena.alloc(Source, rows.len);
    for (rows, out) |r, *s| s.* = fromRow(r);
    return out;
}

fn fromRow(r: Row) Source {
    return .{
        .id = r.id,
        .kind = std.meta.stringToEnum(Kind, r.kind) orelse .ics,
        .name = r.name,
        .url = r.url,
        .color = if (isColor(r.color)) r.color else palette[@intCast(@mod(r.id, palette.len))],
        .visible = r.visible != 0,
        .blocks_booking = r.blocks_booking != 0,
        .in_feed = r.in_feed != 0,
        .synced_at = r.synced_at,
    };
}

pub fn isColor(s: []const u8) bool {
    if (s.len != 7 or s[0] != '#') return false;
    for (s[1..]) |ch| if (!std.ascii.isHex(ch)) return false;
    return true;
}

fn nowText(arena: std.mem.Allocator) ![]const u8 {
    return arena.print("{d}", .{std.Io.Timestamp.now(zx.Io.default(), .real).toSeconds()});
}

pub fn syncIcloud(arena: std.mem.Allocator) !void {
    const creds = (try caldav.loadCredentials(arena)) orelse return error.NotConfigured;
    const found = try caldav.discoverCalendars(arena, creds, origin(creds.calendar_url));
    const now = try nowText(arena);

    for (found) |cal| _ = try zx.db.run(
        \\INSERT INTO calendars (kind, name, url, color, synced_at) VALUES ('icloud', ?1, ?2, ?3, ?4)
        \\ON CONFLICT (url) DO UPDATE SET
        \\  name = excluded.name,
        \\  color = CASE WHEN calendars.color = '' THEN excluded.color ELSE calendars.color END,
        \\  synced_at = excluded.synced_at
    , .{ cal.name, cal.url, cal.color, now });
    // Anything this sync didn't touch is gone from the account.
    _ = try zx.db.run("DELETE FROM calendars WHERE kind = 'icloud' AND synced_at IS NOT ?1", .{now});
    invalidate();
}

pub fn hasIcloudCalendars(arena: std.mem.Allocator) bool {
    const row = zx.db.row(arena, struct { ok: i64 }, "SELECT 1 AS ok FROM calendars WHERE kind = 'icloud' LIMIT 1", .{}) catch return true;
    return row != null;
}

fn origin(url: []const u8) []const u8 {
    const scheme = std.mem.indexOf(u8, url, "://") orelse return "https://caldav.icloud.com/";
    const slash = std.mem.indexOfScalarPos(u8, url, scheme + 3, '/') orelse return url;
    return url[0 .. slash + 1];
}

pub fn normalizeFeedUrl(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const url = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.startsWithIgnoreCase(url, "webcal://")) return arena.print("https://{s}", .{url["webcal://".len..]});
    if (!settings.isHttpUrl(url)) return error.InvalidUrl;
    return url;
}

pub fn addFeed(arena: std.mem.Allocator, raw_url: []const u8, raw_name: []const u8, color: []const u8) !void {
    const url = try normalizeFeedUrl(arena, raw_url);
    if (try isOwnFeed(arena, url)) return error.OwnFeed;
    const body = fetchFeed(arena, url) catch return error.InvalidFeed;
    if (std.mem.indexOf(u8, body, "BEGIN:VCALENDAR") == null) return error.InvalidFeed;

    var name = std.mem.trim(u8, raw_name, " \t\r\n");
    if (name.len == 0) name = feedName(body) orelse "Calendar";
    if (name.len > 100) return error.InvalidName;

    const exists = try zx.db.row(arena, struct { id: i64 }, "SELECT id FROM calendars WHERE url = ?1", .{url});
    if (exists != null) return error.Duplicate;
    _ = try zx.db.run(
        \\INSERT INTO calendars (kind, name, url, color, synced_at) VALUES ('ics', ?1, ?2, ?3, ?4)
    , .{ name, url, if (isColor(color)) color else "", try nowText(arena) });
    invalidate();
}

fn feedName(ics: []const u8) ?[]const u8 {
    const key = "X-WR-CALNAME:";
    const at = std.mem.indexOf(u8, ics, key) orelse return null;
    const rest = ics[at + key.len ..];
    const name = std.mem.trim(u8, rest[0 .. std.mem.indexOfAny(u8, rest, "\r\n") orelse rest.len], " \t");
    return if (name.len > 0 and name.len <= 100) name else null;
}

pub const Update = struct { name: []const u8, color: []const u8, visible: bool, blocks_booking: bool, in_feed: bool };

pub fn update(id: i64, u: Update) !void {
    const name = std.mem.trim(u8, u.name, " \t\r\n");
    if (name.len == 0 or name.len > 100) return error.InvalidName;
    if (!isColor(u.color)) return error.InvalidColor;
    _ = try zx.db.run(
        \\UPDATE calendars SET name = ?2, color = ?3, visible = ?4, blocks_booking = ?5, in_feed = ?6 WHERE id = ?1
    , .{ id, name, u.color, @as(i64, @intFromBool(u.visible)), @as(i64, @intFromBool(u.blocks_booking)), @as(i64, @intFromBool(u.in_feed)) });
    invalidate();
}

// iCloud calendars would come back on the next sync; those can only be hidden.
pub fn removeFeed(id: i64) !void {
    _ = try zx.db.run("DELETE FROM calendars WHERE id = ?1 AND kind = 'ics'", .{id});
    invalidate();
}

pub const Prefs = struct {
    // Cached events older than this are refetched.
    stale_minutes: i64 = 5,
    week_start: slots.Weekday = .sun,

    pub fn staleSeconds(self: Prefs) i64 {
        return self.stale_minutes * std.time.s_per_min;
    }
};

pub fn loadPrefs(arena: std.mem.Allocator) Prefs {
    var prefs: Prefs = .{};
    const rows = zx.db.rows(arena, struct { key: []const u8, val: []const u8 },
        \\SELECT key, val FROM settings WHERE key IN ('calendar_stale_minutes', 'calendar_week_start')
    , .{}) catch return prefs;
    for (rows) |r| {
        if (std.mem.eql(u8, r.key, "calendar_stale_minutes")) prefs.stale_minutes = std.fmt.parseInt(i64, r.val, 10) catch prefs.stale_minutes;
        if (std.mem.eql(u8, r.key, "calendar_week_start")) prefs.week_start = std.meta.stringToEnum(slots.Weekday, r.val) orelse prefs.week_start;
    }
    return prefs;
}

pub fn savePrefs(arena: std.mem.Allocator, prefs: Prefs) !void {
    if (prefs.stale_minutes < 1 or prefs.stale_minutes > 24 * 60) return error.InvalidPrefs;
    const put =
        \\INSERT INTO settings (key, val) VALUES (?1, ?2) ON CONFLICT (key) DO UPDATE SET val = excluded.val
    ;
    _ = try zx.db.run(put, .{ "calendar_stale_minutes", try arena.print("{d}", .{prefs.stale_minutes}) });
    _ = try zx.db.run(put, .{ "calendar_week_start", @tagName(prefs.week_start) });
    invalidate();
}

// One cached copy per calendar covers `window(now)`; every view reads from it, so
// a feed is fetched and parsed once per refresh instead of once per range.
// `max_age` null takes any cached copy, 0 always fetches. `at` is when the events
// were fetched.
const keep_s = 30 * std.time.s_per_day;

pub fn window(now: i64) Interval {
    const start = week.weekStart(now, .sun) - 5 * std.time.s_per_week;
    return .{ .start = start, .end = start + 32 * std.time.s_per_week };
}

const Cached = struct { at: i64, window: Interval, events: []const ical.Event };

pub const Fetched = struct { events: []const ical.Event, at: i64, failed: bool = false };

pub fn events(arena: std.mem.Allocator, creds: ?caldav.Credentials, source: Source, range: Interval, max_age: ?i64) !Fetched {
    const now = std.Io.Timestamp.now(zx.Io.default(), .real).toSeconds();
    const win = window(now);
    // Weeks far from today aren't worth caching.
    if (range.start < win.start or range.end > win.end)
        return .{ .events = try fetchEvents(arena, creds, source.kind, source.url, range), .at = now };

    const kv = zx.kv.scoped(.calendar);
    const key = try arena.print("events:{d}", .{source.id});
    const cached: ?Cached = if (try kv.get(arena, key)) |raw| zx.util.zxon.parse(Cached, arena, raw, .{}) catch null else null;
    if (cached) |c| if (std.meta.eql(c.window, win) and (max_age == null or now - c.at <= max_age.?))
        return .{ .events = try overlapping(arena, c.events, range), .at = c.at };

    const found = fetchEvents(arena, creds, source.kind, source.url, win) catch |err| {
        const c = cached orelse return err;
        zx.log.warn("calendar: refreshing {s} failed, using the cached copy: {any}", .{ source.name, err });
        return .{ .events = try overlapping(arena, c.events, range), .at = c.at, .failed = true };
    };
    var encoded: std.Io.Writer.Allocating = .init(arena);
    try zx.util.zxon.serialize(Cached{ .at = now, .window = win, .events = found }, &encoded.writer, .{});
    kv.put(key, encoded.written(), .{ .ttl = .fromSeconds(keep_s) }) catch |err|
        zx.log.warn("calendar: failed to cache events of {s}: {any}", .{ source.name, err });
    return .{ .events = try overlapping(arena, found, range), .at = now };
}

fn overlapping(arena: std.mem.Allocator, all: []const ical.Event, range: Interval) ![]const ical.Event {
    var out: std.ArrayList(ical.Event) = .empty;
    for (all) |ev| if (ev.end > range.start and ev.start < range.end) try out.append(arena, ev);
    return out.items;
}

fn fetchEvents(arena: std.mem.Allocator, creds: ?caldav.Credentials, kind: Kind, url: []const u8, range: Interval) ![]const ical.Event {
    return switch (kind) {
        .icloud => ical.events(arena, try caldav.eventsIn(arena, creds orelse return error.NotConfigured, url, range), range, .xml),
        .ics => ical.events(arena, try fetchFeed(arena, url), range, .raw),
    };
}

pub const Loaded = struct {
    source: Source,
    events: []const ical.Event,
    failed: bool,
    at: i64,
};

pub fn loadVisible(arena: std.mem.Allocator, range: Interval, max_age: ?i64) ![]const Loaded {
    const creds = caldav.loadCredentials(arena) catch null;
    var out: std.ArrayList(Loaded) = .empty;
    for (try list(arena)) |source| {
        if (!source.visible) continue;
        const got = events(arena, creds, source, range, max_age) catch |err| blk: {
            zx.log.warn("calendar: loading {s} failed: {any}", .{ source.name, err });
            break :blk Fetched{ .events = &.{}, .at = 0, .failed = true };
        };
        try out.append(arena, .{ .source = source, .events = got.events, .failed = got.failed, .at = got.at });
    }
    return out.toOwnedSlice(arena);
}

const busy_key = "busy";

// Only the booking calendar must load; the others are best-effort.
pub fn busy(arena: std.mem.Allocator, creds: caldav.Credentials, range: Interval, use_cache: bool) ![]const Interval {
    const kv = zx.kv.scoped(.schedule);
    if (use_cache) if (try kv.get(arena, busy_key)) |cached| {
        if (zx.util.zxon.parse([]const Interval, arena, cached, .{})) |intervals| return intervals else |_| {}
    };

    var out: std.ArrayList(Interval) = .empty;
    try appendBusy(arena, &out, try fetchEvents(arena, creds, .icloud, creds.calendar_url, range));

    const others = list(arena) catch |err| blk: {
        zx.log.warn("schedule: failed to list calendars: {any}", .{err});
        break :blk &.{};
    };
    const max_age: i64 = if (use_cache) loadPrefs(arena).staleSeconds() else 0;
    for (others) |source| {
        if (!source.blocks_booking or sameCalendar(source.url, creds.calendar_url)) continue;
        const got = events(arena, creds, source, range, max_age) catch |err| {
            zx.log.warn("schedule: busy times of {s} failed: {any}", .{ source.name, err });
            continue;
        };
        try appendBusy(arena, &out, got.events);
    }

    var encoded: std.Io.Writer.Allocating = .init(arena);
    try zx.util.zxon.serialize(out.items, &encoded.writer, .{});
    kv.put(busy_key, encoded.written(), .{ .ttl = .fromSeconds(120) }) catch |err|
        zx.log.warn("schedule: failed to cache busy times: {any}", .{err});
    return out.items;
}

fn appendBusy(arena: std.mem.Allocator, out: *std.ArrayList(Interval), found: []const ical.Event) !void {
    for (found) |ev| if (ev.busy) try out.append(arena, .{ .start = ev.start, .end = ev.end });
}

// iCloud hands out the same calendar under different hosts (caldav. vs pNN-caldav.).
fn sameCalendar(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, std.mem.trimEnd(u8, caldav.urlPath(a), "/"), std.mem.trimEnd(u8, caldav.urlPath(b), "/"));
}

pub fn invalidateBusy() void {
    zx.kv.scoped(.schedule).delete(busy_key) catch {};
}

fn invalidate() void {
    invalidateBusy();
    inline for (comptime std.enums.values(feed.Detail)) |d| zx.kv.scoped(.calendar).delete(feed_key ++ @tagName(d)) catch {};
}

pub const Detail = feed.Detail;

pub const Link = struct {
    id: i64,
    label: []const u8,
    detail: Detail,
    created_at: []const u8,
    last_used_at: ?[]const u8,
};

const LinkRow = struct { id: i64, label: []const u8, detail: []const u8, created_at: []const u8, last_used_at: ?[]const u8 };

fn linkFromRow(r: LinkRow) Link {
    return .{
        .id = r.id,
        .label = r.label,
        .detail = std.meta.stringToEnum(Detail, r.detail) orelse .busy,
        .created_at = r.created_at,
        .last_used_at = r.last_used_at,
    };
}

pub fn listLinks(arena: std.mem.Allocator) ![]const Link {
    const rows = try zx.db.rows(arena, LinkRow,
        \\SELECT id, label, detail, created_at, last_used_at FROM calendar_feeds ORDER BY id
    , .{});
    const out = try arena.alloc(Link, rows.len);
    for (rows, out) |r, *l| l.* = linkFromRow(r);
    return out;
}

// Only the hash is stored, so the returned token can never be shown again.
pub fn createLink(arena: std.mem.Allocator, raw_label: []const u8, detail: Detail) ![]const u8 {
    const label = std.mem.trim(u8, raw_label, " \t\r\n");
    if (label.len == 0 or label.len > 60) return error.InvalidName;

    var random: [24]u8 = undefined;
    zx.Io.default().random(&random);
    const encoder = std.base64.url_safe_no_pad.Encoder;
    const token = try arena.alloc(u8, encoder.calcSize(random.len));
    _ = encoder.encode(token, &random);

    var hash: [64]u8 = undefined;
    _ = try zx.db.run(
        \\INSERT INTO calendar_feeds (label, token_hash, detail) VALUES (?1, ?2, ?3)
    , .{ label, hashToken(&hash, token), @tagName(detail) });
    return token;
}

pub fn revokeLink(id: i64) !void {
    _ = try zx.db.run("DELETE FROM calendar_feeds WHERE id = ?1", .{id});
}

pub fn findLink(arena: std.mem.Allocator, token: []const u8) !?Link {
    if (token.len == 0 or token.len > 128) return null;
    var hash: [64]u8 = undefined;
    const row = try zx.db.row(arena, LinkRow,
        \\SELECT id, label, detail, created_at, last_used_at FROM calendar_feeds WHERE token_hash = ?1
    , .{hashToken(&hash, token)}) orelse return null;
    return linkFromRow(row);
}

pub fn touchLink(arena: std.mem.Allocator, id: i64) void {
    _ = zx.db.run("UPDATE calendar_feeds SET last_used_at = ?2 WHERE id = ?1", .{ id, nowText(arena) catch return }) catch |err|
        zx.log.warn("calendar: failed to record feed use: {any}", .{err});
}

fn hashToken(buf: *[64]u8, token: []const u8) []const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &digest, .{});
    return std.fmt.bufPrint(buf, "{x}", .{digest[0..]}) catch unreachable;
}

// Our own feed as a source would make the feed include itself.
fn isOwnFeed(arena: std.mem.Allocator, url: []const u8) !bool {
    const path = caldav.urlPath(url);
    const prefix = "/calendar/";
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    var name = path[prefix.len..];
    name = name[0 .. std.mem.indexOfAny(u8, name, "?#") orelse name.len];
    if (std.mem.endsWith(u8, name, ".ics")) name = name[0 .. name.len - ".ics".len];
    return (try findLink(arena, name)) != null;
}

const feed_key = "feed:";
const feed_ttl_s = 600;

// Cached only when every calendar loaded, so a hiccup doesn't stick around.
pub fn renderFeed(arena: std.mem.Allocator, detail: Detail, now: i64) ![]const u8 {
    const kv = zx.kv.scoped(.calendar);
    const cache_key = try arena.print(feed_key ++ "{s}", .{@tagName(detail)});
    if (try kv.get(arena, cache_key)) |cached| return cached;

    const prefs = loadPrefs(arena);
    const range = window(now);
    const creds = caldav.loadCredentials(arena) catch null;

    var items: std.ArrayList(feed.Item) = .empty;
    var complete = true;
    for (try list(arena)) |source| {
        if (!source.in_feed) continue;
        const got = events(arena, creds, source, range, prefs.staleSeconds()) catch |err| {
            zx.log.warn("calendar: feed skipped {s}: {any}", .{ source.name, err });
            complete = false;
            continue;
        };
        if (got.failed) complete = false;
        for (got.events) |ev| try items.append(arena, .{
            .uid = try occurrenceUid(arena, source.id, ev),
            .start = ev.start,
            .end = ev.end,
            .all_day = ev.all_day,
            .busy = ev.busy,
            .summary = ev.summary,
            .location = ev.location,
        });
    }

    var out: std.Io.Writer.Allocating = .init(arena);
    const name = switch (detail) {
        .full => "Nurul Huda (Apon)",
        .busy => "Nurul Huda (Apon) - Busy",
    };
    try feed.write(&out.writer, name, items.items, detail, now);
    if (complete) kv.put(cache_key, out.written(), .{ .ttl = .fromSeconds(feed_ttl_s) }) catch |err|
        zx.log.warn("calendar: failed to cache feed: {any}", .{err});
    return out.written();
}

// Opaque, so busy-only feeds don't leak event UIDs.
fn occurrenceUid(arena: std.mem.Allocator, source_id: i64, ev: ical.Event) ![]const u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [64]u8 = undefined;
    h.update(std.fmt.bufPrint(&buf, "{d}|{d}|", .{ source_id, ev.start }) catch unreachable);
    h.update(if (ev.uid.len > 0) ev.uid else ev.summary);
    const digest = h.finalResult();
    return arena.print("{x}@nurulhudaapon.com", .{digest[0..16]});
}

fn fetchFeed(arena: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client: zx.http.Client = .{ .io = zx.Io.default(), .allocator = arena };
    defer client.deinit();
    const response = try client.fetch(.{
        .url = url,
        .headers = &.{
            .{ .name = "User-Agent", .value = "nurulhudaapon.com" },
            .{ .name = "Accept", .value = "text/calendar, */*" },
        },
        .timeout = .{ .duration = .{ .raw = .fromMilliseconds(15_000), .clock = .awake } },
    });
    defer response.deinit(arena);
    if (response.status.class() != .success) {
        zx.log.warn("calendar: GET {s} failed status={d}", .{ url, @backingInt(response.status) });
        return error.FeedError;
    }
    return arena.dupe(u8, response.body);
}

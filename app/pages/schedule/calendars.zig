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

fn timestamp(arena: std.mem.Allocator, now: i64) ![]const u8 {
    return arena.print("{d}", .{now});
}

pub fn syncIcloud(arena: std.mem.Allocator, io: std.Io) !void {
    const creds = (try caldav.credentials(arena)) orelse return error.NotConfigured;
    const client: caldav.Client = .{ .arena = arena, .io = io, .creds = creds };
    const found = try client.discover(origin(creds.calendar_url));
    const now = try timestamp(arena, std.Io.Timestamp.now(io, .real).toSeconds());

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

pub fn hasIcloud(arena: std.mem.Allocator) bool {
    const row = zx.db.row(arena, struct { ok: i64 }, "SELECT 1 AS ok FROM calendars WHERE kind = 'icloud' LIMIT 1", .{}) catch return true;
    return row != null;
}

fn origin(url: []const u8) []const u8 {
    const scheme = std.mem.indexOf(u8, url, "://") orelse return "https://caldav.icloud.com/";
    const slash = std.mem.indexOfScalarPos(u8, url, scheme + 3, '/') orelse return url;
    return url[0 .. slash + 1];
}

fn normalizeUrl(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const url = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.startsWithIgnoreCase(url, "webcal://")) return arena.print("https://{s}", .{url["webcal://".len..]});
    if (!settings.isHttpUrl(url)) return error.InvalidUrl;
    return url;
}

pub fn addFeed(arena: std.mem.Allocator, io: std.Io, raw_url: []const u8, raw_name: []const u8, color: []const u8) !void {
    const url = try normalizeUrl(arena, raw_url);
    if (try isOwnFeed(arena, url)) return error.OwnFeed;
    const body = fetchFeed(arena, io, url) catch return error.InvalidFeed;
    if (std.mem.indexOf(u8, body, "BEGIN:VCALENDAR") == null) return error.InvalidFeed;

    var name = std.mem.trim(u8, raw_name, " \t\r\n");
    if (name.len == 0) name = feedName(body) orelse "Calendar";
    if (name.len > 100) return error.InvalidName;

    const exists = try zx.db.row(arena, struct { id: i64 }, "SELECT id FROM calendars WHERE url = ?1", .{url});
    if (exists != null) return error.Duplicate;
    _ = try zx.db.run(
        \\INSERT INTO calendars (kind, name, url, color, synced_at) VALUES ('ics', ?1, ?2, ?3, ?4)
    , .{ name, url, if (isColor(color)) color else "", try timestamp(arena, std.Io.Timestamp.now(io, .real).toSeconds()) });
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

    pub fn load(arena: std.mem.Allocator) Prefs {
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

    pub fn save(self: Prefs, arena: std.mem.Allocator) !void {
        if (self.stale_minutes < 1 or self.stale_minutes > 24 * 60) return error.InvalidPrefs;
        const put =
            \\INSERT INTO settings (key, val) VALUES (?1, ?2) ON CONFLICT (key) DO UPDATE SET val = excluded.val
        ;
        _ = try zx.db.run(put, .{ "calendar_stale_minutes", try arena.print("{d}", .{self.stale_minutes}) });
        _ = try zx.db.run(put, .{ "calendar_week_start", @tagName(self.week_start) });
        invalidate();
    }
};

// Each calendar is synced as one cached copy covering `window(now)`, months at a
// time. Pages only read these copies; when one is missing or older than the
// "refresh after" setting they ask for a sync (`requestSync`), which main.ts runs
// on a Worker queue through /internal/calendar/sync. `at` is when it was fetched.
const keep_s = 60 * std.time.s_per_day;

pub fn window(now: i64) Interval {
    const start = week.start(now, .sun) - 9 * std.time.s_per_week;
    return .{ .start = start, .end = start + 36 * std.time.s_per_week };
}

const Copy = struct { at: i64, window: Interval, events: []const ical.Event };

const Cached = struct { events: []const ical.Event, at: i64, stale: bool };

fn eventsKey(arena: std.mem.Allocator, id: i64) ![]const u8 {
    return arena.print("events:{d}", .{id});
}

// Never fetches: a missing or outdated copy comes back empty or as is, with `stale` set.
fn cached(arena: std.mem.Allocator, source: Source, range: Interval, prefs: Prefs, now: i64) !Cached {
    const raw = try zx.kv.scoped(.calendar).get(arena, try eventsKey(arena, source.id)) orelse
        return .{ .events = &.{}, .at = 0, .stale = true };
    const c = zx.util.zxon.parse(Copy, arena, raw, .{}) catch
        return .{ .events = &.{}, .at = 0, .stale = true };
    return .{
        .events = try overlapping(arena, c.events, range),
        .at = c.at,
        .stale = now - c.at > prefs.staleSeconds() or !std.meta.eql(c.window, window(now)),
    };
}

fn overlapping(arena: std.mem.Allocator, all: []const ical.Event, range: Interval) ![]const ical.Event {
    var out: std.ArrayList(ical.Event) = .empty;
    for (all) |ev| if (ev.end > range.start and ev.start < range.end) try out.append(arena, ev);
    return out.items;
}

fn fetchEvents(arena: std.mem.Allocator, io: std.Io, creds: ?caldav.Credentials, kind: Kind, url: []const u8, range: Interval) ![]const ical.Event {
    switch (kind) {
        .icloud => {
            const client: caldav.Client = .{ .arena = arena, .io = io, .creds = creds orelse return error.NotConfigured };
            return ical.events(arena, try client.events(url, range), range, .xml);
        },
        .ics => return ical.events(arena, try fetchFeed(arena, io, url), range, .raw),
    }
}

// Fetches one calendar's window and caches it. Runs from the queue consumer.
pub fn sync(arena: std.mem.Allocator, io: std.Io, id: i64) !void {
    const row = try zx.db.row(arena, Row, select_cols ++ " WHERE id = ?1", .{id}) orelse return; // removed since
    const source = fromRow(row);
    const now = std.Io.Timestamp.now(io, .real).toSeconds();
    const win = window(now);
    const found = try fetchEvents(arena, io, caldav.credentials(arena) catch null, source.kind, source.url, win);

    var encoded: std.Io.Writer.Allocating = .init(arena);
    try zx.util.zxon.serialize(Copy{ .at = now, .window = win, .events = found }, &encoded.writer, .{});
    try zx.kv.scoped(.calendar).put(try eventsKey(arena, id), encoded.written(), .{ .ttl = .fromSeconds(keep_s) });
    invalidate();
}

fn syncAll(arena: std.mem.Allocator, io: std.Io) void {
    const sources = list(arena) catch |err| return zx.log.err("calendar: sync failed to list calendars: {any}", .{err});
    for (sources) |s| sync(arena, io, s.id) catch |err|
        zx.log.err("calendar: syncing {s} failed: {any}", .{ s.name, err });
}

// main.ts turns this response header into one queue message per calendar id.
pub const sync_header = "x-calendar-sync";
const sync_key = "sync:requested";
// Pages read often; one request per this long is plenty.
const sync_cooldown_s = 120;

// Returns when the sync was asked for, so a caller can wait for copies newer
// than it. Repeats within the cooldown reuse the earlier request unless `force`.
// Without the queue (`zig build dev`), syncs right here.
pub fn requestSync(arena: std.mem.Allocator, io: std.Io, response: anytype, force: bool) i64 {
    const now = std.Io.Timestamp.now(io, .real).toSeconds();
    if (!zx.platform.isWasm()) {
        syncAll(arena, io);
        return now;
    }
    const kv = zx.kv.scoped(.calendar);
    if (!force) if (kv.get(arena, sync_key) catch null) |raw| {
        const at = std.fmt.parseInt(i64, raw, 10) catch 0;
        if (now - at < sync_cooldown_s) return at;
    };
    const sources = list(arena) catch return now;
    var ids: std.ArrayList(u8) = .empty;
    for (sources, 0..) |s, i| ids.print(arena, "{s}{d}", .{ if (i > 0) "," else "", s.id }) catch return now;
    if (ids.items.len == 0) return now;

    kv.put(sync_key, arena.print("{d}", .{now}) catch return now, .{ .ttl = .fromSeconds(sync_cooldown_s) }) catch {};
    response.headers.append(sync_header, ids.items);
    return now;
}

pub const Loaded = struct {
    source: Source,
    events: []const ical.Event,
    stale: bool,
    at: i64,
};

pub fn visible(arena: std.mem.Allocator, range: Interval, now: i64) ![]const Loaded {
    const prefs: Prefs = .load(arena);
    var out: std.ArrayList(Loaded) = .empty;
    for (try list(arena)) |source| {
        if (!source.visible) continue;
        const got = try cached(arena, source, range, prefs, now);
        try out.append(arena, .{ .source = source, .events = got.events, .stale = got.stale, .at = got.at });
    }
    return out.toOwnedSlice(arena);
}

const busy_key = "busy";

pub const Busy = struct { intervals: []const Interval, stale: bool };

// Busy time on /schedule: calendars set to block booking, from the synced
// copies, plus bookings made since the last sync. `live` (when booking) asks
// iCloud for the booking calendar itself instead of trusting its copy.
pub fn busy(arena: std.mem.Allocator, io: std.Io, creds: caldav.Credentials, range: Interval, live: bool) !Busy {
    const kv = zx.kv.scoped(.schedule);
    if (!live) if (try kv.get(arena, busy_key)) |raw| {
        if (zx.util.zxon.parse(Busy, arena, raw, .{})) |b| return b else |_| {}
    };

    var out: std.ArrayList(Interval) = .empty;
    var stale = false;
    if (live) try appendBusy(arena, &out, try fetchEvents(arena, io, creds, .icloud, creds.calendar_url, range));

    const prefs: Prefs = .load(arena);
    const now = std.Io.Timestamp.now(io, .real).toSeconds();
    for (try list(arena)) |source| {
        const booking_calendar = caldav.sameCalendar(source.url, creds.calendar_url);
        if (!source.blocks_booking and !booking_calendar) continue;
        if (live and booking_calendar) continue;
        const got = try cached(arena, source, range, prefs, now);
        stale = stale or got.stale;
        try appendBusy(arena, &out, got.events);
    }

    const booked = try zx.db.rows(arena, struct { starts_at: i64, ends_at: i64 },
        \\SELECT starts_at, ends_at FROM bookings WHERE cancelled_at IS NULL AND ends_at > ?1 AND starts_at < ?2
    , .{ range.start, range.end });
    for (booked) |b| try out.append(arena, .{ .start = b.starts_at, .end = b.ends_at });

    const result: Busy = .{ .intervals = out.items, .stale = stale };
    if (!live) {
        var encoded: std.Io.Writer.Allocating = .init(arena);
        try zx.util.zxon.serialize(result, &encoded.writer, .{});
        // Dropped on every sync and booking, so it can live as long as the copies.
        kv.put(busy_key, encoded.written(), .{ .ttl = .fromSeconds(prefs.staleSeconds()) }) catch |err|
            zx.log.warn("schedule: failed to cache busy times: {any}", .{err});
    }
    return result;
}

fn appendBusy(arena: std.mem.Allocator, out: *std.ArrayList(Interval), found: []const ical.Event) !void {
    for (found) |ev| if (ev.busy) try out.append(arena, .{ .start = ev.start, .end = ev.end });
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

    const Record = struct { id: i64, label: []const u8, detail: []const u8, created_at: []const u8, last_used_at: ?[]const u8 };

    fn fromRecord(r: Record) Link {
        return .{
            .id = r.id,
            .label = r.label,
            .detail = std.meta.stringToEnum(Detail, r.detail) orelse .busy,
            .created_at = r.created_at,
            .last_used_at = r.last_used_at,
        };
    }

    pub fn list(arena: std.mem.Allocator) ![]const Link {
        const rows = try zx.db.rows(arena, Record,
            \\SELECT id, label, detail, created_at, last_used_at FROM calendar_feeds ORDER BY id
        , .{});
        const out = try arena.alloc(Link, rows.len);
        for (rows, out) |r, *l| l.* = fromRecord(r);
        return out;
    }

    // Only the hash is stored, so the returned token can never be shown again.
    pub fn create(arena: std.mem.Allocator, io: std.Io, raw_label: []const u8, detail: Detail) ![]const u8 {
        const label = std.mem.trim(u8, raw_label, " \t\r\n");
        if (label.len == 0 or label.len > 60) return error.InvalidName;

        var random: [24]u8 = undefined;
        io.random(&random);
        const encoder = std.base64.url_safe_no_pad.Encoder;
        const token = try arena.alloc(u8, encoder.calcSize(random.len));
        _ = encoder.encode(token, &random);

        var hash: [64]u8 = undefined;
        _ = try zx.db.run(
            \\INSERT INTO calendar_feeds (label, token_hash, detail) VALUES (?1, ?2, ?3)
        , .{ label, hashToken(&hash, token), @tagName(detail) });
        return token;
    }

    pub fn revoke(id: i64) !void {
        _ = try zx.db.run("DELETE FROM calendar_feeds WHERE id = ?1", .{id});
    }

    pub fn find(arena: std.mem.Allocator, token: []const u8) !?Link {
        if (token.len == 0 or token.len > 128) return null;
        var hash: [64]u8 = undefined;
        const row = try zx.db.row(arena, Record,
            \\SELECT id, label, detail, created_at, last_used_at FROM calendar_feeds WHERE token_hash = ?1
        , .{hashToken(&hash, token)}) orelse return null;
        return fromRecord(row);
    }

    pub fn touch(self: Link, arena: std.mem.Allocator, now: i64) void {
        _ = zx.db.run("UPDATE calendar_feeds SET last_used_at = ?2 WHERE id = ?1", .{ self.id, timestamp(arena, now) catch return }) catch |err|
            zx.log.warn("calendar: failed to record feed use: {any}", .{err});
    }
};

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
    return (try Link.find(arena, name)) != null;
}

const feed_key = "feed:";

pub const Feed = struct { body: []const u8, stale: bool };

// Cached only when every copy is current; any sync drops it.
pub fn renderFeed(arena: std.mem.Allocator, detail: Detail, now: i64) !Feed {
    const kv = zx.kv.scoped(.calendar);
    const cache_key = try arena.print(feed_key ++ "{s}", .{@tagName(detail)});
    if (try kv.get(arena, cache_key)) |body| return .{ .body = body, .stale = false };

    const prefs: Prefs = .load(arena);
    const range = window(now);

    var items: std.ArrayList(feed.Item) = .empty;
    var stale = false;
    for (try list(arena)) |source| {
        if (!source.in_feed) continue;
        const got = try cached(arena, source, range, prefs, now);
        stale = stale or got.stale;
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
    if (!stale) kv.put(cache_key, out.written(), .{ .ttl = .fromSeconds(prefs.staleSeconds()) }) catch |err|
        zx.log.warn("calendar: failed to cache feed: {any}", .{err});
    return .{ .body = out.written(), .stale = stale };
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

fn fetchFeed(arena: std.mem.Allocator, io: std.Io, url: []const u8) ![]const u8 {
    var client: zx.http.Client = .{ .io = io, .allocator = arena };
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

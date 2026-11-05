const std = @import("std");
const zx = @import("zx");
const format = @import("../format.zig");
const slots = @import("../../schedule/slots.zig");
const ical = @import("../../schedule/ical.zig");
const week = @import("../../schedule/week.zig");
const settings = @import("../../schedule/settings.zig");
const calendars = @import("../../schedule/calendars.zig");

const Interval = slots.Interval;
pub const day_s = std.time.s_per_day;

// `stale` and `forced` ask the client to request a sync; `waiting` has it poll
// until every copy is newer than `since`. See page.zx.
pub const Sync = enum { idle, stale, forced, waiting };

pub const WeekState = struct {
    start: i64,
    href: []const u8,
    loading: bool = false,
    sync: Sync = .idle,
    since: i64 = 0,
    // Fetch time of the oldest copy shown; 0 when one was never synced.
    synced_at: i64 = 0,
    has_calendars: bool,
    err: []const u8 = "",
    view: View,
    alloc_open: bool = false,
    alloc_loading: bool = false,
    alloc: []const AllocRow = &.{},
};

pub fn load(arena: zx.Allocator, now: i64, start: i64, with_alloc: bool) !WeekState {
    const range: Interval = .{ .start = start, .end = start + 7 * day_s };
    const prefs: calendars.Prefs = .load(arena);
    const loaded = try calendars.visible(arena, range, now);
    const v = try build(arena, loaded, settings.load(arena), range, now);
    var stale = false;
    var synced_at: i64 = std.math.maxInt(i64);
    for (loaded) |l| {
        stale = stale or l.stale;
        synced_at = @min(synced_at, l.at);
    }
    var buf: [10]u8 = undefined;
    return .{
        .start = start,
        .href = if (start == week.start(now, prefs.week_start))
            "/admin/calendar"
        else
            try arena.print("/admin/calendar?week={s}", .{week.formatDate(&buf, start)}),
        .sync = if (stale) .stale else .idle,
        .synced_at = if (loaded.len > 0) synced_at else now,
        .has_calendars = loaded.len > 0,
        .err = if (v.unsynced.len > 0) try arena.print("{s} not synced yet.", .{v.unsynced}) else "",
        .view = v,
        .alloc_open = with_alloc,
        .alloc = if (with_alloc) try allocationRows(arena, loaded, range) else &.{},
    };
}

pub fn allocation(arena: zx.Allocator, now: i64, start: i64) ![]const AllocRow {
    const range: Interval = .{ .start = start, .end = start + 7 * day_s };
    return allocationRows(arena, try calendars.visible(arena, range, now), range);
}

pub const Chip = struct { title: []const u8, style: []const u8 };
pub const Block = struct { title: []const u8, time: []const u8, tooltip: []const u8, class: []const u8, style: []const u8 };
pub const Hour = struct { label: []const u8, style: []const u8 };

pub const Day = struct {
    weekday: []const u8,
    date: []const u8,
    summary: []const u8,
    head_class: []const u8,
    all_day: []const Chip,
    blocks: []const Block,
    work_style: ?[]const u8,
    now_style: ?[]const u8,
};

pub const AllocRow = struct {
    name: []const u8,
    count: []const u8,
    hours: []const u8,
    pct: []const u8,
    swatch: []const u8,
    bar: []const u8,
    seconds: i64,
};

pub const View = struct {
    title: []const u8,
    grid_style: []const u8,
    hours: []const Hour,
    days: []const Day,
    unsynced: []const u8,
    busy_total: []const u8,
    busy_hint: []const u8,
    busy_work: []const u8,
    free_total: []const u8,
    capacity: []const u8,
    load_pct: []const u8,
};

const Item = struct { ev: ical.Event, color: []const u8, calendar: []const u8 };

fn build(arena: zx.Allocator, loaded: []const calendars.Loaded, rules: slots.Rules, range: Interval, now: i64) !View {
    var items: std.ArrayList(Item) = .empty;
    var unsynced: std.ArrayList(u8) = .empty;
    for (loaded) |l| {
        if (l.at == 0) {
            if (unsynced.items.len > 0) try unsynced.appendSlice(arena, ", ");
            try unsynced.appendSlice(arena, l.source.name);
        }
        for (l.events) |ev| if (ev.end > range.start and ev.start < range.end)
            try items.append(arena, .{ .ev = ev, .color = l.source.color, .calendar = l.source.name });
    }

    // Visible hours: 08–20, widened to working hours and any timed event.
    var first_min: i64 = @min(8 * 60, rules.day_start);
    var last_min: i64 = @max(20 * 60, rules.day_end);
    for (items.items) |it| {
        if (it.ev.all_day) continue;
        var ds = range.start;
        while (ds < range.end) : (ds += day_s) {
            const s = @max(it.ev.start, ds);
            const e = @min(it.ev.end, ds + day_s);
            if (e <= s) continue;
            first_min = @min(first_min, @divFloor(s - ds, 60));
            last_min = @max(last_min, @divFloor(e - ds + 59, 60) + 20);
        }
    }
    const h0 = @divFloor(first_min, 60);
    const h1 = @min(24, @divFloor(last_min + 59, 60));
    const span_min: f64 = @floatFromInt((h1 - h0) * 60);

    const hours = try arena.alloc(Hour, @intCast(h1 - h0));
    for (hours, 0..) |*h, i| {
        const hour = h0 + @as(i64, @intCast(i));
        h.* = .{
            .label = if (i == 0) "" else try arena.print("{d:0>2}:00", .{@as(u64, @intCast(hour))}),
            .style = try arena.print("top:{d:.3}%", .{@as(f64, @floatFromInt(i * 60)) / span_min * 100}),
        };
    }

    var busy_all: std.ArrayList(Interval) = .empty;
    var busy_timed: std.ArrayList(Interval) = .empty;
    var timed_count: usize = 0;
    for (items.items) |it| {
        if (!it.ev.all_day) timed_count += 1;
        if (!it.ev.busy) continue;
        const iv: Interval = .{ .start = it.ev.start, .end = it.ev.end };
        try busy_all.append(arena, iv);
        if (!it.ev.all_day) try busy_timed.append(arena, iv);
    }

    var capacity: i64 = 0;
    var busy_work: i64 = 0;
    const days = try arena.alloc(Day, 7);
    for (days, 0..) |*d, i| {
        const ds = range.start + @as(i64, @intCast(i)) * day_s;
        const local = slots.LocalDate.of(ds);
        const is_today = now >= ds and now < ds + day_s;
        const open = rules.open_days.contains(local.weekday);
        const work: Interval = .{ .start = ds + rules.day_start * 60, .end = ds + rules.day_end * 60 };

        const day_busy = try week.coveredSeconds(arena, busy_timed.items, .{ .start = ds, .end = ds + day_s });
        var summary = if (day_busy > 0) try arena.print("{s} busy", .{try week.formatDuration(arena, day_busy)}) else "Clear";
        if (open) {
            const in_work = try week.coveredSeconds(arena, busy_all.items, work);
            capacity += work.end - work.start;
            busy_work += in_work;
            summary = try arena.print("{s} · {s} free", .{ summary, try week.formatDuration(arena, work.end - work.start - in_work) });
        }

        d.* = .{
            .weekday = local.weekdayName(),
            .date = try arena.print("{s} {d}", .{ local.monthName(), local.day }),
            .summary = summary,
            .head_class = if (is_today) "adm-cal-head adm-cal-today" else "adm-cal-head",
            .all_day = try allDayChips(arena, items.items, ds),
            .blocks = try dayBlocks(arena, items.items, ds, h0, span_min),
            .work_style = if (open) try bandStyle(arena, rules.day_start, rules.day_end, h0, span_min) else null,
            .now_style = if (is_today) blk: {
                const m = @divFloor(now - ds, 60);
                if (m < h0 * 60 or m > h1 * 60) break :blk null;
                break :blk try arena.print("top:{d:.3}%", .{@as(f64, @floatFromInt(m - h0 * 60)) / span_min * 100});
            } else null,
        };
    }

    const busy_secs = try week.coveredSeconds(arena, busy_timed.items, range);

    const first = slots.LocalDate.of(range.start);
    const last = slots.LocalDate.of(range.end - day_s);
    return .{
        .title = if (first.month == last.month)
            try arena.print("{s} {d} – {d}, {d}", .{ first.monthName(), first.day, last.day, last.year })
        else
            try arena.print("{s} {d} – {s} {d}, {d}", .{ first.monthName(), first.day, last.monthName(), last.day, last.year }),
        .grid_style = try arena.print("--cal-hours:{d}", .{h1 - h0}),
        .hours = hours,
        .days = days,
        .unsynced = unsynced.items,
        .busy_total = try week.formatDuration(arena, busy_secs),
        .busy_hint = try arena.print("{d} timed {s} across {d} {s}", .{
            timed_count, if (timed_count == 1) "event" else "events",
            loaded.len,  if (loaded.len == 1) "calendar" else "calendars",
        }),
        .busy_work = try week.formatDuration(arena, busy_work),
        .free_total = try week.formatDuration(arena, capacity - busy_work),
        .capacity = try week.formatDuration(arena, capacity),
        .load_pct = if (capacity > 0)
            try arena.print("{d:.0}%", .{@as(f64, @floatFromInt(busy_work)) / @as(f64, @floatFromInt(capacity)) * 100})
        else
            "–",
    };
}

fn allDayChips(arena: zx.Allocator, items: []const Item, ds: i64) ![]const Chip {
    var out: std.ArrayList(Chip) = .empty;
    for (items) |it| {
        if (!it.ev.all_day or it.ev.end <= ds or it.ev.start >= ds + day_s) continue;
        try out.append(arena, .{
            .title = if (it.ev.summary.len > 0) it.ev.summary else "(no title)",
            .style = try arena.print("--c:{s}", .{it.color}),
        });
    }
    return out.items;
}

fn dayBlocks(arena: zx.Allocator, items: []const Item, ds: i64, h0: i64, span_min: f64) ![]const Block {
    const Piece = struct { span: Interval, item: Item };
    var pieces: std.ArrayList(Piece) = .empty;
    for (items) |it| {
        if (it.ev.all_day) continue;
        const s = @max(it.ev.start, ds);
        const e = @min(it.ev.end, ds + day_s);
        if (e > s) try pieces.append(arena, .{ .span = .{ .start = s, .end = e }, .item = it });
    }
    std.mem.sort(Piece, pieces.items, {}, struct {
        fn lt(_: void, a: Piece, b: Piece) bool {
            return week.byStart({}, a.span, b.span);
        }
    }.lt);

    const spans = try arena.alloc(Interval, pieces.items.len);
    for (pieces.items, spans) |p, *s| s.* = p.span;
    const lanes = try week.layout(arena, spans);

    const out = try arena.alloc(Block, pieces.items.len);
    for (pieces.items, lanes, out) |p, lane, *b| {
        const top_min: f64 = @floatFromInt(@divFloor(p.span.start - ds, 60) - h0 * 60);
        const len_min: f64 = @floatFromInt(@divFloor(p.span.end - p.span.start, 60));
        const width = 100 / @as(f64, @floatFromInt(lane.lanes));
        const title = if (p.item.ev.summary.len > 0) p.item.ev.summary else "(no title)";
        const time = format.timeRange(arena, p.item.ev.start, p.item.ev.end);
        b.* = .{
            .title = title,
            .time = time,
            .tooltip = try arena.print("{s}\n{s} · {s}{s}", .{ title, time, p.item.calendar, if (p.item.ev.busy) "" else " · free" }),
            .class = try std.mem.concat(arena, u8, &.{
                "adm-cal-ev",
                if (p.item.ev.busy) "" else " adm-cal-ev-free",
                if (len_min < 45) " adm-cal-ev-short" else "",
            }),
            .style = try arena.print("--c:{s};top:{d:.3}%;height:{d:.3}%;left:{d:.2}%;width:{d:.2}%", .{
                p.item.color,
                top_min / span_min * 100,
                len_min / span_min * 100,
                width * @as(f64, @floatFromInt(lane.lane)),
                width,
            }),
        };
    }
    return out;
}

fn bandStyle(arena: zx.Allocator, start_min: i64, end_min: i64, h0: i64, span_min: f64) ![]const u8 {
    const top: f64 = @floatFromInt(start_min - h0 * 60);
    const len: f64 = @floatFromInt(end_min - start_min);
    return arena.print("top:{d:.3}%;height:{d:.3}%", .{ top / span_min * 100, len / span_min * 100 });
}

// Overlaps within a calendar count once.
fn allocationRows(arena: zx.Allocator, loaded: []const calendars.Loaded, range: Interval) ![]const AllocRow {
    var rows: std.ArrayList(AllocRow) = .empty;
    var total: i64 = 0;
    for (loaded) |l| {
        var spans: std.ArrayList(Interval) = .empty;
        for (l.events) |ev| {
            if (ev.all_day or ev.end <= range.start or ev.start >= range.end) continue;
            try spans.append(arena, .{ .start = ev.start, .end = ev.end });
        }
        if (spans.items.len == 0) continue;
        const secs = try week.coveredSeconds(arena, spans.items, range);
        total += secs;
        try rows.append(arena, .{
            .name = l.source.name,
            .count = try arena.print("{d} {s}", .{ spans.items.len, if (spans.items.len == 1) "event" else "events" }),
            .hours = try week.formatDuration(arena, secs),
            .pct = "",
            .swatch = try arena.print("background:{s}", .{l.source.color}),
            .bar = "",
            .seconds = secs,
        });
    }
    std.mem.sort(AllocRow, rows.items, {}, struct {
        fn gt(_: void, a: AllocRow, b: AllocRow) bool {
            return a.seconds > b.seconds;
        }
    }.gt);
    for (rows.items) |*r| {
        const pct = if (total > 0) @as(f64, @floatFromInt(r.seconds)) / @as(f64, @floatFromInt(total)) * 100 else 0;
        r.pct = try arena.print("{d:.0}%", .{pct});
        r.bar = try arena.print("width:{d:.1}%;background:{s}", .{ pct, r.swatch["background:".len..] });
    }
    return rows.items;
}

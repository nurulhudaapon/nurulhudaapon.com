pub fn GET(ctx: zx.RouteContext) !void {
    const accounts = try finance.listAllAccounts(ctx.arena);

    var aw = std.Io.Writer.Allocating.init(ctx.arena);
    const w = &aw.writer;
    try w.writeAll("id,name,type,institution,broker,group,asset_class,currency,balance,cash,value_usd,weight_pct,liability,stale,opened_on,updated_at,notes\r\n");
    for (accounts) |a| {
        try w.print("{d},", .{a.id});
        try writeText(w, a.name);
        try writeText(w, a.type_label);
        try writeText(w, a.institution);
        try writeText(w, a.broker);
        try writeText(w, a.group_name);
        try writeText(w, a.asset_class);
        try writeText(w, a.currency);
        try w.print("{d:.2},{d:.2},{d:.2},{d:.2},{d},{d},", .{
            a.net_liquidation,
            a.cash,
            a.value_usd,
            a.weight_pct,
            a.liability,
            a.stale,
        });
        try writeText(w, a.opened_on orelse "");
        try writeText(w, if (a.synced_at) |at| isoTime(ctx.arena, at) else "");
        try writeField(w, a.notes orelse "");
        try w.writeAll("\r\n");
    }

    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.headers.append("Content-Disposition", "attachment; filename=\"accounts.csv\"");
    ctx.response.setContentType(.@"text/csv");
    ctx.response.text(aw.written());
}

fn writeText(w: *std.Io.Writer, value: []const u8) !void {
    try writeField(w, value);
    try w.writeByte(',');
}

// RFC 4180 quoting, plus a leading quote on text a spreadsheet would run as a formula.
fn writeField(w: *std.Io.Writer, value: []const u8) !void {
    const formula = value.len > 0 and std.mem.indexOfScalar(u8, "=+-@", value[0]) != null;
    const quote = formula or std.mem.indexOfAny(u8, value, ",\"\r\n") != null;
    if (!quote) return w.writeAll(value);
    try w.writeByte('"');
    if (formula) try w.writeByte('\'');
    for (value) |c| {
        if (c == '"') try w.writeByte('"');
        try w.writeByte(c);
    }
    try w.writeByte('"');
}

fn isoTime(arena: std.mem.Allocator, raw: []const u8) []const u8 {
    const unix = std.fmt.parseInt(i64, raw, 10) catch return raw;
    const secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(unix, 0)) };
    const year_day = secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = secs.getDaySeconds();
    return arena.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch raw;
}

pub const options: zx.RouteOptions = .{ .rendering = .request };

const std = @import("std");
const zx = @import("zx");
const finance = @import("../../../finance/db.zig");

const std = @import("std");
const zx = @import("zx");
const fx = @import("fx.zig");

pub const gold_nisab_grams: f64 = 85;

pub const Entry = struct {
    id: i64,
    year: i64,
    amount: f64,
    currency: []const u8,
    paid_on: ?[]const u8,
    notes: ?[]const u8,
};

pub fn list(arena: std.mem.Allocator) ![]const Entry {
    return try zx.db.rows(arena, Entry,
        \\SELECT id, year, amount, currency, paid_on, notes
        \\FROM zakat_entries
        \\ORDER BY year DESC, id DESC
    , .{});
}

pub fn get(arena: std.mem.Allocator, id: i64) !?Entry {
    return try zx.db.row(arena, Entry,
        \\SELECT id, year, amount, currency, paid_on, notes
        \\FROM zakat_entries WHERE id = ?1
    , .{id});
}

pub fn save(arena: std.mem.Allocator, id: i64, year: i64, amount: f64, currency: []const u8, paid_on: []const u8, notes: []const u8) !void {
    if (year < 1900 or year > 2100) return error.InvalidYear;
    if (amount < 0) return error.InvalidAmount;
    const cur = std.mem.trim(u8, currency, " \t\r\n");
    if (cur.len == 0 or !fx.isSupported(arena, cur)) return error.InvalidCurrency;
    const paid = std.mem.trim(u8, paid_on, " \t\r\n");
    const note = std.mem.trim(u8, notes, " \t\r\n");

    if (id == 0) {
        _ = try zx.db.run(
            \\INSERT INTO zakat_entries (year, amount, currency, paid_on, notes)
            \\VALUES (?1, ?2, ?3, ?4, ?5)
            \\ON CONFLICT(year) DO UPDATE SET
            \\  amount = excluded.amount,
            \\  currency = excluded.currency,
            \\  paid_on = excluded.paid_on,
            \\  notes = excluded.notes
        , .{ year, amount, cur, if (paid.len > 0) paid else null, if (note.len > 0) note else null });
        return;
    }
    _ = try zx.db.run(
        \\UPDATE zakat_entries
        \\SET year = ?1, amount = ?2, currency = ?3, paid_on = ?4, notes = ?5
        \\WHERE id = ?6
    , .{ year, amount, cur, if (paid.len > 0) paid else null, if (note.len > 0) note else null, id });
}

pub fn delete(id: i64) !void {
    _ = try zx.db.run("DELETE FROM zakat_entries WHERE id = ?1", .{id});
}

pub fn goldGrams(arena: std.mem.Allocator) f64 {
    const row = zx.db.row(arena, struct { grams: f64 },
        \\SELECT COALESCE(SUM(net_liquidation), 0) AS grams
        \\FROM accounts WHERE UPPER(currency) = 'XAU' AND COALESCE(stale, 0) = 0
    , .{}) catch return 0;
    return if (row) |r| r.grams else 0;
}

pub fn due(net_worth_usd: f64) f64 {
    return @max(0, net_worth_usd) * 0.025;
}

const std = @import("std");
const zx = @import("zx");
const classes = @import("classes.zig");

pub const Target = struct {
    id: i64,
    name: []const u8,
    target_pct: f64,
    sort_order: i64,
    notes: ?[]const u8,
};

pub const Actual = struct {
    name: []const u8,
    target_pct: f64,
    actual_value: f64,
    actual_pct: f64,
    sort_order: i64,
};

pub fn targets(arena: std.mem.Allocator) ![]const Target {
    return try zx.db.rows(arena, Target,
        \\SELECT id, name, target_pct, sort_order, notes
        \\FROM allocations ORDER BY sort_order, name COLLATE NOCASE
    , .{});
}

pub fn actuals(arena: std.mem.Allocator) ![]const Actual {
    return try zx.db.rows(arena, Actual,
        \\WITH valued AS (
        \\  SELECT
        \\    a.id, a.asset_class,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.net_liquidation
        \\         ELSE a.net_liquidation / COALESCE(NULLIF(fx.rate, 0), 1) END AS value_usd,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.cash
        \\         ELSE a.cash / COALESCE(NULLIF(fx.rate, 0), 1) END AS cash_usd,
        \\    EXISTS (
        \\      SELECT 1 FROM holdings h
        \\      WHERE h.account_id = a.id AND h.market_value_base > 0.005
        \\    ) AS has_holdings
        \\  FROM accounts a
        \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
        \\  LEFT JOIN account_types t ON t.id = a.account_type
        \\  WHERE COALESCE(a.stale, 0) = 0 AND COALESCE(t.liability, 0) = 0
        \\),
        \\holding_parts AS (
        \\  SELECT COALESCE(
        \\      (SELECT ac.asset_class FROM asset_class_aliases ac
        \\        WHERE ac.alias = h.category COLLATE NOCASE),
        \\      'Alternatives'
        \\    ) AS name,
        \\    SUM(h.market_value_base) AS value
        \\  FROM holdings h
        \\  JOIN valued v ON v.id = h.account_id
        \\  WHERE h.market_value_base > 0.005
        \\  GROUP BY 1
        \\),
        \\cash_held AS (
        \\  SELECT 'Cash' AS name, SUM(cash_usd) AS value
        \\  FROM valued WHERE has_holdings AND cash_usd > 0.005
        \\),
        \\cash_plain AS (
        \\  SELECT 'Cash' AS name, SUM(cash_usd) AS value
        \\  FROM valued WHERE NOT has_holdings AND cash_usd > 0.005
        \\),
        \\rest_plain AS (
        \\  SELECT COALESCE(
        \\      (SELECT ac.asset_class FROM asset_class_aliases ac
        \\        WHERE ac.alias = v.asset_class COLLATE NOCASE),
        \\      'Alternatives'
        \\    ) AS name,
        \\    SUM(value_usd - cash_usd) AS value
        \\  FROM valued v
        \\  WHERE NOT has_holdings AND (value_usd - cash_usd) > 0.005
        \\  GROUP BY 1
        \\),
        \\parts AS (
        \\  SELECT name, value FROM holding_parts
        \\  UNION ALL SELECT name, value FROM cash_held
        \\  UNION ALL SELECT name, value FROM cash_plain
        \\  UNION ALL SELECT name, value FROM rest_plain
        \\),
        \\by_class AS (
        \\  SELECT name, SUM(value) AS actual_value
        \\  FROM parts GROUP BY name HAVING SUM(value) > 0.005
        \\),
        \\net AS (
        \\  SELECT COALESCE(SUM(value_usd), 0) AS net_worth FROM valued
        \\)
        \\SELECT
        \\  b.name,
        \\  COALESCE(a.target_pct, 0) AS target_pct,
        \\  b.actual_value,
        \\  CASE WHEN n.net_worth > 0 THEN b.actual_value * 100.0 / n.net_worth ELSE 0 END AS actual_pct,
        \\  COALESCE(a.sort_order, 99) AS sort_order
        \\FROM by_class b
        \\CROSS JOIN net n
        \\LEFT JOIN allocations a ON a.name = b.name
        \\ORDER BY COALESCE(a.sort_order, 99), b.name COLLATE NOCASE
    , .{});
}

pub fn save(arena: std.mem.Allocator, id: i64, name: []const u8, target_pct: f64, notes: []const u8) !void {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidName;
    if (target_pct < 0 or target_pct > 100) return error.InvalidPct;
    try classes.ensure(arena, trimmed);

    if (id == 0) {
        const order_row = try zx.db.row(arena, struct { n: i64 },
            \\SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM allocations
        , .{});
        _ = try zx.db.run(
            \\INSERT INTO allocations (name, target_pct, sort_order, notes)
            \\VALUES (?1, ?2, ?3, ?4)
        , .{ trimmed, target_pct, if (order_row) |r| r.n else 1, if (notes.len > 0) notes else null });
        return;
    }

    _ = try zx.db.run(
        \\UPDATE allocations SET name = ?1, target_pct = ?2, notes = ?3 WHERE id = ?4
    , .{ trimmed, target_pct, if (notes.len > 0) notes else null, id });
}

pub fn delete(id: i64) !void {
    _ = try zx.db.run("DELETE FROM allocations WHERE id = ?1", .{id});
}

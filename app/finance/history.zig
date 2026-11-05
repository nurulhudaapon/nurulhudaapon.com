const std = @import("std");
const zx = @import("zx");

// Rows are written only when a balance changes, so the latest row at or before
// a day is that day's balance. Accounts with `opened_at` reach back to it.
pub fn record() !void {
    _ = try zx.db.run(
        \\DELETE FROM balance_history
        \\WHERE recorded_at < (SELECT a.opened_at FROM accounts a WHERE a.id = account_id)
    , .{});
    _ = try zx.db.run(
        \\INSERT INTO balance_history (account_id, recorded_at, balance)
        \\SELECT a.id, a.opened_at, COALESCE((
        \\  SELECT h.balance FROM balance_history h
        \\  WHERE h.account_id = a.id ORDER BY h.recorded_at LIMIT 1), a.net_liquidation)
        \\FROM accounts a
        \\WHERE a.opened_at IS NOT NULL AND NOT EXISTS (
        \\  SELECT 1 FROM balance_history h
        \\  WHERE h.account_id = a.id AND h.recorded_at <= a.opened_at)
    , .{});
    _ = try zx.db.run(
        \\INSERT INTO balance_history (account_id, recorded_at, balance)
        \\SELECT a.id, unixepoch('now', 'start of day'), a.net_liquidation
        \\FROM accounts a
        \\WHERE a.net_liquidation IS NOT (
        \\  SELECT h.balance FROM balance_history h
        \\  WHERE h.account_id = a.id ORDER BY h.recorded_at DESC LIMIT 1)
        \\ON CONFLICT (account_id, recorded_at) DO UPDATE SET balance = excluded.balance
    , .{});
}

// `date` is YYYY-MM-DD (UTC).
pub const DatedBalance = struct { date: []const u8, balance: f64 };

// Broker history overwrites what was recorded that day.
pub fn importBalances(account_id: i64, opened_on: ?[]const u8, points: []const DatedBalance) !void {
    if (opened_on) |d| _ = try zx.db.run(
        \\UPDATE accounts SET opened_at = unixepoch(?1) WHERE id = ?2 AND opened_at IS NULL
    , .{ d, account_id });
    for (points) |p| _ = try zx.db.run(
        \\INSERT INTO balance_history (account_id, recorded_at, balance)
        \\VALUES (?1, unixepoch(?2), ?3)
        \\ON CONFLICT (account_id, recorded_at) DO UPDATE SET balance = excluded.balance
    , .{ account_id, p.date, p.balance });
}

pub const NetWorthPoint = struct {
    t: i64,
    date: []const u8,
    net_worth: f64,
    assets: f64,
    liabilities: f64,
    // At least `change_days` old: the newest such point is the comparison base.
    past: bool,
};

// About 180 evenly spaced days from the first recorded balance to today, valued
// at current FX so only balance changes move the line.
pub fn netWorth(arena: std.mem.Allocator, change_days: u32) ![]const NetWorthPoint {
    return try zx.db.rows(arena, NetWorthPoint,
        \\WITH RECURSIVE
        \\bounds AS (
        \\  SELECT MIN(recorded_at) AS start, unixepoch('now', 'start of day') AS today,
        \\    MAX(86400, (unixepoch('now', 'start of day') - MIN(recorded_at)) / 180 / 86400 * 86400) AS step
        \\  FROM balance_history
        \\),
        \\days(t) AS (
        \\  SELECT start FROM bounds WHERE start IS NOT NULL
        \\  UNION ALL
        \\  SELECT MIN(t + step, today) FROM days, bounds WHERE t < today
        \\),
        \\valued AS (
        \\  SELECT d.t, COALESCE(ty.liability, 0) AS liability,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN h.balance
        \\         ELSE h.balance / COALESCE(NULLIF(fx.rate, 0), 1) END AS usd
        \\  FROM days d
        \\  JOIN accounts a ON COALESCE(a.stale, 0) = 0
        \\  JOIN balance_history h ON h.account_id = a.id AND h.recorded_at = (
        \\    SELECT MAX(recorded_at) FROM balance_history
        \\    WHERE account_id = a.id AND recorded_at <= d.t)
        \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
        \\  LEFT JOIN account_types ty ON ty.id = a.account_type
        \\)
        \\SELECT t, date(t, 'unixepoch') AS date,
        \\  SUM(CASE WHEN liability = 1 THEN -usd ELSE usd END) AS net_worth,
        \\  SUM(CASE WHEN liability = 1 THEN 0 ELSE usd END) AS assets,
        \\  SUM(CASE WHEN liability = 1 THEN usd ELSE 0 END) AS liabilities,
        \\  t <= unixepoch('now', 'start of day', '-' || ?1 || ' days') AS past
        \\FROM valued GROUP BY t ORDER BY t
    , .{change_days});
}

pub const BalancePoint = struct { t: i64, date: []const u8, balance: f64, recorded: bool };

// Newest first, led by today's balance when no row was recorded today.
pub fn balances(arena: std.mem.Allocator, account_id: i64, limit: usize) ![]const BalancePoint {
    return try zx.db.rows(arena, BalancePoint,
        \\SELECT t, date, balance, recorded FROM (
        \\  SELECT recorded_at AS t, date(recorded_at, 'unixepoch') AS date, balance, 1 AS recorded
        \\  FROM balance_history WHERE account_id = ?1
        \\  UNION ALL
        \\  SELECT unixepoch('now', 'start of day'), date('now'), net_liquidation, 0
        \\  FROM accounts WHERE id = ?1 AND NOT EXISTS (
        \\    SELECT 1 FROM balance_history
        \\    WHERE account_id = ?1 AND recorded_at = unixepoch('now', 'start of day'))
        \\)
        \\ORDER BY t DESC LIMIT ?2
    , .{ account_id, limit });
}

const std = @import("std");
const zx = @import("zx");
const accounts = @import("accounts.zig");
const allocations = @import("allocations.zig");
const holdings = @import("holdings.zig");

const fallback_usd_bdt: f64 = 122;

pub const Summary = struct {
    net_worth: f64,
    assets_total: f64,
    liabilities_total: f64,
    cash_total: f64,
    invested_total: f64,
    account_count: usize,
    holding_count: usize,
    last_synced: ?[]const u8,
    usd_bdt_rate: f64,
    net_worth_bdt: f64,
    fx_as_of: ?i64,
};

const Totals = struct {
    net_worth: f64 = 0,
    assets_total: f64 = 0,
    liabilities_total: f64 = 0,
    cash_total: f64 = 0,
    account_count: i64 = 0,
    holding_count: i64 = 0,
    last_synced: ?[]const u8 = null,
    usd_bdt_rate: f64 = fallback_usd_bdt,
    fx_as_of: i64 = 0,
};

pub fn summary(arena: std.mem.Allocator) !Summary {
    const t = (try zx.db.row(arena, Totals,
        \\WITH valued AS (
        \\  SELECT
        \\    a.id, a.account_type, a.asset_class, a.synced_at, COALESCE(a.stale, 0) AS stale,
        \\    COALESCE(t.liability, 0) AS liability,
        \\    CASE WHEN COALESCE(t.liability, 0) = 1 THEN -1.0 ELSE 1.0 END *
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.net_liquidation
        \\         ELSE a.net_liquidation / COALESCE(NULLIF(fx.rate, 0), 1) END AS value_usd,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.cash
        \\         ELSE a.cash / COALESCE(NULLIF(fx.rate, 0), 1) END AS cash_usd
        \\  FROM accounts a
        \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
        \\  LEFT JOIN account_types t ON t.id = a.account_type
        \\  WHERE COALESCE(a.stale, 0) = 0
        \\)
        \\SELECT
        \\  COALESCE(SUM(value_usd), 0) AS net_worth,
        \\  COALESCE(SUM(CASE WHEN liability = 0 THEN value_usd ELSE 0 END), 0) AS assets_total,
        \\  COALESCE(-SUM(CASE WHEN liability = 1 THEN value_usd ELSE 0 END), 0) AS liabilities_total,
        \\  COALESCE(SUM(
        \\    CASE WHEN liability = 1 THEN 0
        \\         WHEN account_type IN ('cash', 'savings') OR asset_class = 'Cash'
        \\         THEN value_usd ELSE cash_usd END
        \\  ), 0) AS cash_total,
        \\  COUNT(*) AS account_count,
        \\  (SELECT COUNT(*) FROM holdings h
        \\     JOIN accounts a2 ON a2.id = h.account_id
        \\    WHERE h.market_value_base > 0.005 AND COALESCE(a2.stale, 0) = 0) AS holding_count,
        \\  MAX(synced_at) AS last_synced,
        \\  COALESCE((SELECT rate FROM fx_rates WHERE currency = 'BDT'), 122) AS usd_bdt_rate,
        \\  COALESCE((SELECT MAX(fetched_at) FROM fx_rates
        \\             WHERE fetched_at > 0 AND as_of NOT IN ('seed', '')), 0) AS fx_as_of
        \\FROM valued
    , .{})) orelse Totals{};

    const rate = if (t.usd_bdt_rate > 0) t.usd_bdt_rate else fallback_usd_bdt;
    return .{
        .net_worth = t.net_worth,
        .assets_total = t.assets_total,
        .liabilities_total = t.liabilities_total,
        .cash_total = t.cash_total,
        .invested_total = @max(0, t.assets_total - t.cash_total),
        .account_count = @intCast(@max(t.account_count, 0)),
        .holding_count = @intCast(@max(t.holding_count, 0)),
        .last_synced = t.last_synced,
        .usd_bdt_rate = rate,
        .net_worth_bdt = t.net_worth * rate,
        .fx_as_of = if (t.fx_as_of > 0) t.fx_as_of else null,
    };
}

pub const Snapshot = struct {
    net_worth: f64,
    cash_total: f64,
    invested_total: f64,
    accounts: []const accounts.Account,
    holdings: []const holdings.Holding,
    allocations: []const allocations.Actual,
    account_count: usize,
    holding_count: usize,
    last_synced: ?[]const u8,
    usd_bdt_rate: f64,
    net_worth_bdt: f64,
    fx_as_of: ?i64,
};

// Summary totals plus the account list, allocation actuals and top ten holdings.
pub fn snapshot(arena: std.mem.Allocator) !Snapshot {
    const account_list = try accounts.list(arena);
    const actuals = try allocations.actuals(arena);
    const top = try holdings.list(arena, 10);
    const s = try summary(arena);

    return .{
        .net_worth = s.net_worth,
        .cash_total = s.cash_total,
        .invested_total = s.invested_total,
        .accounts = account_list,
        .holdings = top,
        .allocations = actuals,
        .account_count = s.account_count,
        .holding_count = s.holding_count,
        .last_synced = s.last_synced,
        .usd_bdt_rate = s.usd_bdt_rate,
        .net_worth_bdt = s.net_worth_bdt,
        .fx_as_of = s.fx_as_of,
    };
}

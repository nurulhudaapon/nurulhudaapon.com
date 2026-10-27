const std = @import("std");
const zx = @import("zx");
const fx = @import("fx.zig");
const number = @import("number.zig");

pub const AccountType = struct { id: []const u8, label: []const u8 };
pub const AssetClass = struct { name: []const u8 };

pub fn listAccountTypes(arena: std.mem.Allocator) ![]const AccountType {
    return try zx.db.rows(arena, AccountType,
        \\SELECT id, label FROM account_types ORDER BY sort_order, id
    , .{});
}

pub fn listAssetClasses(arena: std.mem.Allocator) ![]const AssetClass {
    return try zx.db.rows(arena, AssetClass,
        \\SELECT name FROM asset_classes ORDER BY sort_order, name COLLATE NOCASE
    , .{});
}

pub fn listCurrencies(arena: std.mem.Allocator) ![]const []const u8 {
    return fx.listCurrencies(arena);
}

pub fn usdBdtRate(arena: std.mem.Allocator) f64 {
    return fx.usdBdtRate(arena);
}

pub const Account = struct {
    id: i64,
    broker: []const u8,
    external_id: []const u8,
    name: []const u8,
    currency: []const u8,
    cash: f64,
    net_liquidation: f64,
    synced_at: ?[]const u8,
    institution: []const u8,
    account_type: []const u8,
    asset_class: []const u8,
    notes: ?[]const u8,
    stale: i64 = 0,
    group_name: []const u8 = "",
    type_label: []const u8 = "",
    liability: i64 = 0,
    opened_at: ?i64 = null,
    opened_on: ?[]const u8 = null,
    // Liabilities are negative here; weight is the share of active assets.
    value_usd: f64 = 0,
    cash_usd: f64 = 0,
    weight_pct: f64 = 0,
};

pub const Holding = struct {
    id: i64,
    account_id: i64,
    account_name: []const u8,
    account_external_id: []const u8,
    symbol: []const u8,
    description: []const u8,
    asset_class: []const u8,
    category: []const u8,
    currency: []const u8,
    quantity: f64,
    market_price: f64,
    market_value: f64,
    market_value_base: f64,
    conid: ?[]const u8,
    synced_at: ?[]const u8,
};

pub const Allocation = struct {
    id: i64,
    name: []const u8,
    target_pct: f64,
    sort_order: i64,
    notes: ?[]const u8,
};

pub const AllocationActual = struct {
    name: []const u8,
    target_pct: f64,
    actual_value: f64,
    actual_pct: f64,
    sort_order: i64,
};

pub const ZakatEntry = struct {
    id: i64,
    year: i64,
    amount: f64,
    currency: []const u8,
    paid_on: ?[]const u8,
    notes: ?[]const u8,
};

pub const gold_nisab_grams: f64 = 85;

pub const Snapshot = struct {
    net_worth: f64,
    cash_total: f64,
    invested_total: f64,
    accounts: []const Account,
    holdings: []const Holding,
    allocations: []const AllocationActual,
    account_count: usize,
    holding_count: usize,
    last_synced: ?[]const u8,
    usd_bdt_rate: f64,
    net_worth_bdt: f64,
    fx_as_of: ?i64,
};

const Filter = union(enum) { all, group: []const u8, id: i64 };

// Weights are against active assets; a single-account lookup also returns
// empty balances that listings hide.
fn queryAccounts(arena: std.mem.Allocator, filter: Filter) ![]const Account {
    const id: i64 = if (filter == .id) filter.id else 0;
    const group: []const u8 = if (filter == .group) filter.group else "";
    return try zx.db.rows(arena, Account,
        \\WITH valued AS (
        \\  SELECT
        \\    a.id, a.broker, a.external_id, a.name, a.currency, a.cash, a.net_liquidation, a.synced_at,
        \\    a.institution, a.account_type, a.asset_class, a.notes, COALESCE(a.stale, 0) AS stale,
        \\    a.group_name, COALESCE(t.label, a.account_type) AS type_label,
        \\    a.opened_at, date(a.opened_at, 'unixepoch') AS opened_on,
        \\    COALESCE(t.liability, 0) AS liability,
        \\    CASE WHEN COALESCE(t.liability, 0) = 1 THEN -1.0 ELSE 1.0 END *
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.net_liquidation
        \\         ELSE a.net_liquidation / COALESCE(NULLIF(fx.rate, 0), 1) END AS value_usd,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.cash
        \\         ELSE a.cash / COALESCE(NULLIF(fx.rate, 0), 1) END AS cash_usd
        \\  FROM accounts a
        \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
        \\  LEFT JOIN account_types t ON t.id = a.account_type
        \\),
        \\tot AS (
        \\  SELECT COALESCE(SUM(CASE WHEN stale = 0 AND liability = 0 THEN value_usd ELSE 0 END), 0) AS active_total
        \\  FROM valued
        \\)
        \\SELECT v.*,
        \\  CASE WHEN v.stale != 0 OR v.liability != 0 OR t.active_total <= 0 THEN 0
        \\       ELSE v.value_usd * 100.0 / t.active_total END AS weight_pct
        \\FROM valued v CROSS JOIN tot t
        \\WHERE CASE WHEN ?1 != 0 THEN v.id = ?1
        \\  ELSE (?2 = '' OR v.group_name = ?2)
        \\   AND (ABS(v.value_usd) > 0.005 OR ABS(v.cash_usd) > 0.005 OR v.stale != 0) END
        \\ORDER BY CASE WHEN v.stale != 0 THEN 1 ELSE 0 END, v.value_usd DESC, v.name COLLATE NOCASE
    , .{ id, group });
}

pub fn listAccounts(arena: std.mem.Allocator) ![]const Account {
    return queryAccounts(arena, .all);
}

pub fn listGroupAccounts(arena: std.mem.Allocator, group_name: []const u8) ![]const Account {
    return queryAccounts(arena, .{ .group = group_name });
}

pub fn getAccount(arena: std.mem.Allocator, id: i64) !?Account {
    const rows = try queryAccounts(arena, .{ .id = id });
    return if (rows.len > 0) rows[0] else null;
}

pub const AccountEntry = union(enum) {
    account: Account,
    group: AccountGroup,

    fn valueUsd(self: AccountEntry) f64 {
        return switch (self) {
            .account => |a| if (isAccountStale(a)) 0 else a.value_usd,
            .group => |g| g.value_usd,
        };
    }

    fn stale(self: AccountEntry) bool {
        return switch (self) {
            .account => |a| isAccountStale(a),
            .group => |g| g.stale_count == g.account_count,
        };
    }
};

// Totals cover active accounts only, like the portfolio totals.
pub const AccountGroup = struct {
    name: []const u8,
    value_usd: f64 = 0,
    weight_pct: f64 = 0,
    account_count: usize = 0,
    stale_count: usize = 0,
};

// Grouped accounts collapse into one entry per group; largest first, stale last.
pub fn listAccountEntries(arena: std.mem.Allocator) ![]const AccountEntry {
    var entries: std.ArrayList(AccountEntry) = .empty;
    for (try listAccounts(arena)) |a| {
        const name = a.group_name;
        if (name.len == 0) {
            try entries.append(arena, .{ .account = a });
            continue;
        }
        const group = for (entries.items) |*e| {
            if (e.* == .group and std.mem.eql(u8, e.group.name, name)) break &e.group;
        } else blk: {
            try entries.append(arena, .{ .group = .{ .name = name } });
            break :blk &entries.items[entries.items.len - 1].group;
        };
        group.account_count += 1;
        if (isAccountStale(a)) {
            group.stale_count += 1;
        } else {
            group.value_usd += a.value_usd;
            group.weight_pct += a.weight_pct;
        }
    }
    std.mem.sort(AccountEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: AccountEntry, b: AccountEntry) bool {
            if (a.stale() != b.stale()) return b.stale();
            return a.valueUsd() > b.valueUsd();
        }
    }.lessThan);
    return entries.items;
}

pub const GroupSummary = struct { name: []const u8, account_count: i64 };

pub fn listAccountGroups(arena: std.mem.Allocator) ![]const GroupSummary {
    return try zx.db.rows(arena, GroupSummary,
        \\SELECT group_name AS name, COUNT(*) AS account_count FROM accounts
        \\WHERE group_name != ''
        \\GROUP BY group_name
        \\ORDER BY group_name COLLATE NOCASE
    , .{});
}

// Renaming onto an existing group merges the two; an empty name ungroups.
pub fn renameGroup(from: []const u8, to: []const u8) !void {
    _ = try zx.db.run(
        \\UPDATE accounts SET group_name = ?2 WHERE group_name = ?1
    , .{ from, std.mem.trim(u8, to, " \t\r\n") });
}

pub fn listHoldings(arena: std.mem.Allocator) ![]const Holding {
    return try listHoldingsLimited(arena, null);
}

pub fn listHoldingsLimited(arena: std.mem.Allocator, limit: ?usize) ![]const Holding {
    if (limit) |n| {
        return try zx.db.rows(arena, Holding,
            \\SELECT h.id, h.account_id, a.name AS account_name, a.external_id AS account_external_id,
            \\       h.symbol, h.description, h.asset_class, h.category, h.currency,
            \\       h.quantity, h.market_price, h.market_value, h.market_value_base, h.conid, h.synced_at
            \\FROM holdings h
            \\JOIN accounts a ON a.id = h.account_id
            \\WHERE h.market_value_base > 0.005 AND COALESCE(a.stale, 0) = 0
            \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
            \\LIMIT ?1
        , .{n});
    }
    return try zx.db.rows(arena, Holding,
        \\SELECT h.id, h.account_id, a.name AS account_name, a.external_id AS account_external_id,
        \\       h.symbol, h.description, h.asset_class, h.category, h.currency,
        \\       h.quantity, h.market_price, h.market_value, h.market_value_base, h.conid, h.synced_at
        \\FROM holdings h
        \\JOIN accounts a ON a.id = h.account_id
        \\WHERE h.market_value_base > 0.005 AND COALESCE(a.stale, 0) = 0
        \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
    , .{});
}

pub fn isLiability(account: Account) bool {
    return account.liability != 0;
}

pub fn isAccountStale(account: Account) bool {
    return account.stale != 0;
}

pub fn listAllocations(arena: std.mem.Allocator) ![]const Allocation {
    return try zx.db.rows(arena, Allocation,
        \\SELECT id, name, target_pct, sort_order, notes
        \\FROM allocations ORDER BY sort_order, name COLLATE NOCASE
    , .{});
}

pub const PortfolioSummary = struct {
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

const SnapshotMeta = struct {
    net_worth: f64,
    assets_total: f64,
    liabilities_total: f64,
    cash_total: f64,
    account_count: i64,
    holding_count: i64,
    last_synced: ?[]const u8,
    usd_bdt_rate: f64,
    fx_as_of: i64,
};

pub fn portfolioSummary(arena: std.mem.Allocator) !PortfolioSummary {
    const meta = (try zx.db.row(arena, SnapshotMeta,
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
    , .{})) orelse SnapshotMeta{
        .net_worth = 0,
        .assets_total = 0,
        .liabilities_total = 0,
        .cash_total = 0,
        .account_count = 0,
        .holding_count = 0,
        .last_synced = null,
        .usd_bdt_rate = 122,
        .fx_as_of = 0,
    };

    const rate = if (meta.usd_bdt_rate > 0) meta.usd_bdt_rate else 122;
    return .{
        .net_worth = meta.net_worth,
        .assets_total = meta.assets_total,
        .liabilities_total = meta.liabilities_total,
        .cash_total = meta.cash_total,
        .invested_total = @max(0, meta.assets_total - meta.cash_total),
        .account_count = @intCast(@max(meta.account_count, 0)),
        .holding_count = @intCast(@max(meta.holding_count, 0)),
        .last_synced = meta.last_synced,
        .usd_bdt_rate = rate,
        .net_worth_bdt = meta.net_worth * rate,
        .fx_as_of = if (meta.fx_as_of > 0) meta.fx_as_of else null,
    };
}

pub fn snapshot(arena: std.mem.Allocator) !Snapshot {
    const accounts = try listAccounts(arena);
    const allocations = try listAllocationActuals(arena);
    const holdings = try listHoldingsLimited(arena, 10);
    const meta = try portfolioSummary(arena);

    return .{
        .net_worth = meta.net_worth,
        .cash_total = meta.cash_total,
        .invested_total = meta.invested_total,
        .accounts = accounts,
        .holdings = holdings,
        .allocations = allocations,
        .account_count = meta.account_count,
        .holding_count = meta.holding_count,
        .last_synced = meta.last_synced,
        .usd_bdt_rate = meta.usd_bdt_rate,
        .net_worth_bdt = meta.net_worth_bdt,
        .fx_as_of = meta.fx_as_of,
    };
}

pub fn listAllocationActuals(arena: std.mem.Allocator) ![]const AllocationActual {
    return try zx.db.rows(arena, AllocationActual,
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

// Rows are written only when a balance changes, so the latest row at or before
// a day is that day's balance. Accounts with `opened_at` reach back to it.
pub fn recordHistory() !void {
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

pub const DatedBalance = struct { date: []const u8, balance: f64 };

// `date` is YYYY-MM-DD (UTC). Broker history overwrites what was recorded that day.
pub fn importHistory(account_id: i64, opened_on: ?[]const u8, points: []const DatedBalance) !void {
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
pub fn listNetWorthHistory(arena: std.mem.Allocator, change_days: u32) ![]const NetWorthPoint {
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
pub fn listBalanceHistory(arena: std.mem.Allocator, account_id: i64, limit: usize) ![]const BalancePoint {
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

pub fn listAccountHoldings(arena: std.mem.Allocator, account_id: i64) ![]const Holding {
    return try zx.db.rows(arena, Holding,
        \\SELECT h.id, h.account_id, a.name AS account_name, a.external_id AS account_external_id,
        \\       h.symbol, h.description, h.asset_class, h.category, h.currency,
        \\       h.quantity, h.market_price, h.market_value, h.market_value_base, h.conid, h.synced_at
        \\FROM holdings h
        \\JOIN accounts a ON a.id = h.account_id
        \\WHERE h.account_id = ?1 AND h.market_value_base > 0.005
        \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
    , .{account_id});
}

pub fn updateBalance(arena: std.mem.Allocator, id: i64, balance: f64) !void {
    if (!std.math.isFinite(balance) or balance < 0) return error.InvalidAmount;
    const result = try zx.db.run(
        \\UPDATE accounts SET net_liquidation = ?1, synced_at = ?2
        \\WHERE id = ?3 AND broker = 'manual'
    , .{ balance, try nowSecs(arena), id });
    if (result.changes == 0) return error.AccountMissing;
}

pub const balance_stale_days = 30;

pub fn needsBalanceUpdate(account: Account, now_secs: i64) bool {
    if (!std.mem.eql(u8, account.broker, "manual") or isAccountStale(account)) return false;
    const at = std.fmt.parseInt(i64, account.synced_at orelse return true, 10) catch return true;
    return now_secs - at > balance_stale_days * std.time.s_per_day;
}

pub fn classAliases(arena: std.mem.Allocator) !std.StringHashMapUnmanaged([]const u8) {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    const rows = try zx.db.rows(arena, struct { alias: []const u8, asset_class: []const u8 },
        \\SELECT alias, asset_class FROM asset_class_aliases
    , .{});
    for (rows) |r| try map.put(arena, r.alias, r.asset_class);
    return map;
}

pub fn resolveClass(aliases: std.StringHashMapUnmanaged([]const u8), name: []const u8) []const u8 {
    var it = aliases.iterator();
    while (it.next()) |kv| {
        if (std.ascii.eqlIgnoreCase(kv.key_ptr.*, name)) return kv.value_ptr.*;
    }
    return "Alternatives";
}

pub const AccountInput = struct {
    id: i64,
    name: []const u8,
    institution: []const u8,
    account_type: []const u8,
    asset_class: []const u8,
    currency: []const u8,
    balance: f64,
    notes: []const u8,
    stale: bool = false,
    group_name: []const u8 = "",
    // YYYY-MM-DD, or empty for unknown.
    opened_on: []const u8 = "",
};

// Synced accounts only take the fields the user owns: asset class, group, notes, stale.
pub fn saveAccount(arena: std.mem.Allocator, input: AccountInput) !i64 {
    if (input.id != 0) {
        const existing = try getAccount(arena, input.id) orelse return error.AccountMissing;
        if (!std.mem.eql(u8, existing.broker, "manual")) {
            if (!try validAssetClass(arena, input.asset_class)) return error.InvalidName;
            const notes = std.mem.trim(u8, input.notes, " \t\r\n");
            _ = try zx.db.run(
                \\UPDATE accounts SET asset_class = ?1, group_name = ?2, notes = ?3, stale = ?4,
                \\  opened_at = unixepoch(NULLIF(?5, ''))
                \\WHERE id = ?6
            , .{
                input.asset_class,
                std.mem.trim(u8, input.group_name, " \t\r\n"),
                if (notes.len > 0) notes else null,
                if (input.stale) @as(i64, 1) else 0,
                input.opened_on,
                input.id,
            });
            return input.id;
        }
    }
    return saveManualAccount(arena, input);
}

fn saveManualAccount(arena: std.mem.Allocator, input: AccountInput) !i64 {
    const name = std.mem.trim(u8, input.name, " \t\r\n");
    if (name.len == 0 or !try validAccountType(arena, input.account_type) or !try validAssetClass(arena, input.asset_class))
        return error.InvalidName;

    const institution = std.mem.trim(u8, input.institution, " \t\r\n");
    const currency = blk: {
        const c = std.mem.trim(u8, input.currency, " \t\r\n");
        const code = if (c.len > 0) c else "USD";
        if (!fx.isSupported(arena, code)) return error.InvalidName;
        break :blk try std.ascii.allocUpperString(arena, code);
    };
    const notes = std.mem.trim(u8, input.notes, " \t\r\n");
    const group_name = std.mem.trim(u8, input.group_name, " \t\r\n");
    const now = try nowSecs(arena);
    const stale: i64 = if (input.stale) 1 else 0;

    if (input.id == 0) {
        const created = try zx.db.run(
            \\INSERT INTO accounts
            \\  (broker, external_id, name, currency, cash, net_liquidation, institution,
            \\   account_type, asset_class, notes, synced_at, stale, group_name, opened_at)
            \\VALUES ('manual', ?1, ?2, ?3, 0, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, unixepoch(NULLIF(?12, '')))
        , .{
            try arena.print("manual-{s}", .{now}),
            name,
            currency,
            input.balance,
            institution,
            input.account_type,
            input.asset_class,
            if (notes.len > 0) notes else null,
            now,
            stale,
            group_name,
            input.opened_on,
        });
        return created.last_insert_id;
    }

    _ = try zx.db.run(
        \\UPDATE accounts SET
        \\  name = ?1, institution = ?2, account_type = ?3, asset_class = ?4,
        \\  currency = ?5, net_liquidation = ?6, notes = ?7, synced_at = ?8, stale = ?9,
        \\  group_name = ?10, opened_at = unixepoch(NULLIF(?11, ''))
        \\WHERE id = ?12 AND broker = 'manual'
    , .{
        name,
        institution,
        input.account_type,
        input.asset_class,
        currency,
        input.balance,
        if (notes.len > 0) notes else null,
        now,
        stale,
        group_name,
        input.opened_on,
        input.id,
    });
    return input.id;
}

pub fn deleteManualAccount(id: i64) !void {
    _ = try zx.db.run("DELETE FROM accounts WHERE id = ?1 AND broker = 'manual'", .{id});
}

pub fn setAccountAssetClass(arena: std.mem.Allocator, id: i64, asset_class: []const u8) !void {
    if (!try validAssetClass(arena, asset_class)) return error.InvalidName;
    _ = try zx.db.run("UPDATE accounts SET asset_class = ?1 WHERE id = ?2", .{ asset_class, id });
}

pub fn setAccountStale(id: i64, stale: bool) !void {
    _ = try zx.db.run("UPDATE accounts SET stale = ?1 WHERE id = ?2", .{ if (stale) @as(i64, 1) else 0, id });
}

pub fn upsertAccount(arena: std.mem.Allocator, account: struct {
    external_id: []const u8,
    name: []const u8,
    currency: []const u8,
    cash: f64,
    net_liquidation: f64,
    synced_at: []const u8,
}) !i64 {
    _ = try zx.db.run(
        \\INSERT INTO accounts
        \\  (broker, external_id, name, currency, cash, net_liquidation, synced_at,
        \\   institution, account_type, asset_class)
        \\VALUES ('ibkr', ?1, ?2, ?3, ?4, ?5, ?6, 'Interactive Brokers', 'brokerage', 'Equities')
        \\ON CONFLICT (broker, external_id) DO UPDATE SET
        \\  name = excluded.name,
        \\  currency = excluded.currency,
        \\  cash = excluded.cash,
        \\  net_liquidation = excluded.net_liquidation,
        \\  synced_at = excluded.synced_at,
        \\  institution = 'Interactive Brokers',
        \\  account_type = 'brokerage'
    , .{ account.external_id, account.name, account.currency, account.cash, account.net_liquidation, account.synced_at });

    const row = try zx.db.row(arena, struct { id: i64 },
        \\SELECT id FROM accounts WHERE broker = 'ibkr' AND external_id = ?1
    , .{account.external_id}) orelse return error.AccountMissing;
    return row.id;
}

pub fn clearIbkrHoldings() !void {
    _ = try zx.db.run(
        \\DELETE FROM holdings
        \\WHERE account_id IN (SELECT id FROM accounts WHERE broker = 'ibkr')
    , .{});
}

pub fn categoryOverrides(arena: std.mem.Allocator) !std.StringHashMapUnmanaged([]const u8) {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    const aliases = try classAliases(arena);
    const rows = try zx.db.rows(arena, struct {
        external_id: []const u8,
        symbol: []const u8,
        category: []const u8,
        asset_class: []const u8,
    },
        \\SELECT a.external_id, h.symbol, h.category, h.asset_class
        \\FROM holdings h
        \\JOIN accounts a ON a.id = h.account_id
        \\WHERE a.broker = 'ibkr'
    , .{});
    for (rows) |row| {
        const default = resolveClass(aliases, row.asset_class);
        if (std.mem.eql(u8, row.category, default)) continue;
        try map.put(arena, try arena.print("{s}\x00{s}", .{ row.external_id, row.symbol }), row.category);
    }
    return map;
}

pub fn insertHolding(holding: struct {
    account_id: i64,
    symbol: []const u8,
    description: []const u8,
    asset_class: []const u8,
    category: []const u8,
    currency: []const u8,
    quantity: f64,
    market_price: f64,
    market_value: f64,
    market_value_base: f64,
    conid: ?[]const u8,
    synced_at: []const u8,
}) !void {
    _ = try zx.db.run(
        \\INSERT INTO holdings
        \\  (account_id, symbol, description, asset_class, category, currency,
        \\   quantity, market_price, market_value, market_value_base, conid, synced_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
    , .{
        holding.account_id,
        holding.symbol,
        holding.description,
        holding.asset_class,
        holding.category,
        holding.currency,
        holding.quantity,
        holding.market_price,
        holding.market_value,
        holding.market_value_base,
        holding.conid,
        holding.synced_at,
    });
}

pub fn saveAllocation(arena: std.mem.Allocator, id: i64, name: []const u8, target_pct: f64, notes: []const u8) !void {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidName;
    if (target_pct < 0 or target_pct > 100) return error.InvalidPct;
    try ensureAssetClass(arena, trimmed);

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

fn ensureAssetClass(arena: std.mem.Allocator, name: []const u8) !void {
    if (try validAssetClass(arena, name)) return;
    const order_row = try zx.db.row(arena, struct { n: i64 },
        \\SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM asset_classes
    , .{});
    _ = try zx.db.run(
        \\INSERT OR IGNORE INTO asset_classes (name, sort_order) VALUES (?1, ?2)
    , .{ name, if (order_row) |r| r.n else 100 });
}

pub fn deleteAllocation(id: i64) !void {
    _ = try zx.db.run("DELETE FROM allocations WHERE id = ?1", .{id});
}

pub fn listZakat(arena: std.mem.Allocator) ![]const ZakatEntry {
    return try zx.db.rows(arena, ZakatEntry,
        \\SELECT id, year, amount, currency, paid_on, notes
        \\FROM zakat_entries
        \\ORDER BY year DESC, id DESC
    , .{});
}

pub fn getZakat(arena: std.mem.Allocator, id: i64) !?ZakatEntry {
    return try zx.db.row(arena, ZakatEntry,
        \\SELECT id, year, amount, currency, paid_on, notes
        \\FROM zakat_entries WHERE id = ?1
    , .{id});
}

pub fn saveZakat(arena: std.mem.Allocator, id: i64, year: i64, amount: f64, currency: []const u8, paid_on: []const u8, notes: []const u8) !void {
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

pub fn deleteZakat(id: i64) !void {
    _ = try zx.db.run("DELETE FROM zakat_entries WHERE id = ?1", .{id});
}

pub fn goldGrams(arena: std.mem.Allocator) f64 {
    const row = zx.db.row(arena, struct { grams: f64 },
        \\SELECT COALESCE(SUM(net_liquidation), 0) AS grams
        \\FROM accounts WHERE UPPER(currency) = 'XAU' AND COALESCE(stale, 0) = 0
    , .{}) catch return 0;
    return if (row) |r| r.grams else 0;
}

pub fn zakatDueUsd(net_worth_usd: f64) f64 {
    return @max(0, net_worth_usd) * 0.025;
}

pub fn categoryForAssetClass(aliases: std.StringHashMapUnmanaged([]const u8), asset_class: []const u8) []const u8 {
    return resolveClass(aliases, asset_class);
}

fn validAccountType(arena: std.mem.Allocator, v: []const u8) !bool {
    const row = try zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM account_types WHERE id = ?1 LIMIT 1
    , .{v});
    return row != null;
}

fn validAssetClass(arena: std.mem.Allocator, v: []const u8) !bool {
    const row = try zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM asset_classes WHERE name = ?1 LIMIT 1
    , .{v});
    return row != null;
}

fn nowSecs(arena: std.mem.Allocator) ![]const u8 {
    return try arena.print("{d}", .{std.Io.Timestamp.now(zx.io(), .real).toSeconds()});
}

pub fn formatMoney(arena: std.mem.Allocator, amount: f64, currency: []const u8) []const u8 {
    const abs = @abs(amount);
    const sign: []const u8 = if (amount < 0) "-" else "";
    if (fx.isMetal(currency)) {
        if (@abs(abs - @round(abs)) < 0.0005)
            return arena.print("{s}{d} g", .{ sign, @as(i64, @intFromFloat(@round(abs))) }) catch "";
        return arena.print("{s}{d:.2} g", .{ sign, abs }) catch "";
    }
    const whole: u64 = @intFromFloat(@floor(abs));
    var frac: u64 = @intFromFloat(@round((abs - @floor(abs)) * 100.0));
    if (frac >= 100) frac = 99;
    if (std.ascii.eqlIgnoreCase(currency, "BDT")) {
        const digits = number.groupDigits(arena, whole, .south_asian);
        if (frac == 0) return arena.print("{s}৳{s}", .{ sign, digits }) catch "";
        return arena.print("{s}৳{s}.{d:0>2}", .{ sign, digits, frac }) catch "";
    }
    const digits = number.groupDigits(arena, whole, .western);
    if (std.ascii.eqlIgnoreCase(currency, "JPY"))
        return arena.print("{s}¥{s}", .{ sign, digits }) catch "";
    if (std.ascii.eqlIgnoreCase(currency, "USD"))
        return arena.print("{s}${s}.{d:0>2}", .{ sign, digits, frac }) catch "";
    return arena.print("{s}{s} {s}.{d:0>2}", .{ sign, currency, digits, frac }) catch "";
}

pub fn formatPct(arena: std.mem.Allocator, pct: f64) []const u8 {
    const rounded: i64 = @intFromFloat(@round(pct * 10.0));
    return arena.print("{d}.{d}%", .{ @divTrunc(rounded, 10), @mod(@abs(rounded), 10) }) catch "";
}

pub fn formatQty(arena: std.mem.Allocator, qty: f64) []const u8 {
    const sign: []const u8 = if (qty < 0) "-" else "";
    const abs = @abs(qty);
    if (@abs(abs - @round(abs)) < 0.0001)
        return arena.print("{s}{s}", .{ sign, number.groupDigits(arena, @intFromFloat(@round(abs)), .western) }) catch "";
    const whole: u64 = @intFromFloat(@floor(abs));
    const frac: u64 = @min(9999, @as(u64, @intFromFloat(@round((abs - @floor(abs)) * 10000.0))));
    return arena.print("{s}{s}.{d:0>4}", .{ sign, number.groupDigits(arena, whole, .western), frac }) catch "";
}

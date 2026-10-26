const std = @import("std");
const zx = @import("zx");
const fx = @import("fx.zig");

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

pub const AccountRow = struct {
    account: Account,
    value_usd: f64,
    cash_usd: f64,
    weight_pct: f64,
};

pub const Snapshot = struct {
    net_worth: f64,
    cash_total: f64,
    invested_total: f64,
    accounts: []const AccountRow,
    holdings: []const Holding,
    allocations: []const AllocationActual,
    account_count: usize,
    holding_count: usize,
    last_synced: ?[]const u8,
    usd_bdt_rate: f64,
    net_worth_bdt: f64,
    fx_as_of: ?i64,
};

pub fn listAccounts(arena: std.mem.Allocator) ![]const Account {
    return try zx.db.rows(arena, Account,
        \\SELECT id, broker, external_id, name, currency, cash, net_liquidation, synced_at,
        \\       institution, account_type, asset_class, notes
        \\FROM accounts
        \\ORDER BY name COLLATE NOCASE
    , .{});
}

const AccountUsdRow = struct {
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
    value_usd: f64,
    cash_usd: f64,
    weight_pct: f64,
};

pub fn listAccountRows(arena: std.mem.Allocator) ![]const AccountRow {
    // Do not call fx.refresh here — portfolio GETs must stay D1-only on Workers.
    const rows = try zx.db.rows(arena, AccountUsdRow,
        \\WITH valued AS (
        \\  SELECT
        \\    a.id, a.broker, a.external_id, a.name, a.currency, a.cash, a.net_liquidation, a.synced_at,
        \\    a.institution, a.account_type, a.asset_class, a.notes,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.net_liquidation
        \\         ELSE a.net_liquidation / COALESCE(NULLIF(fx.rate, 0), 1) END AS value_usd,
        \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.cash
        \\         ELSE a.cash / COALESCE(NULLIF(fx.rate, 0), 1) END AS cash_usd
        \\  FROM accounts a
        \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
        \\)
        \\SELECT
        \\  id, broker, external_id, name, currency, cash, net_liquidation, synced_at,
        \\  institution, account_type, asset_class, notes, value_usd, cash_usd,
        \\  CASE WHEN SUM(value_usd) OVER () > 0 THEN value_usd * 100.0 / SUM(value_usd) OVER () ELSE 0 END AS weight_pct
        \\FROM valued
        \\WHERE ABS(value_usd) > 0.005 OR ABS(cash_usd) > 0.005
        \\ORDER BY value_usd DESC, name COLLATE NOCASE
    , .{});

    const out = try arena.alloc(AccountRow, rows.len);
    for (rows, 0..) |r, i| {
        out[i] = .{
            .account = .{
                .id = r.id,
                .broker = r.broker,
                .external_id = r.external_id,
                .name = r.name,
                .currency = r.currency,
                .cash = r.cash,
                .net_liquidation = r.net_liquidation,
                .synced_at = r.synced_at,
                .institution = r.institution,
                .account_type = r.account_type,
                .asset_class = r.asset_class,
                .notes = r.notes,
            },
            .value_usd = r.value_usd,
            .cash_usd = r.cash_usd,
            .weight_pct = r.weight_pct,
        };
    }
    return out;
}

pub fn listHoldings(arena: std.mem.Allocator) ![]const Holding {
    return try zx.db.rows(arena, Holding,
        \\SELECT h.id, h.account_id, a.name AS account_name, a.external_id AS account_external_id,
        \\       h.symbol, h.description, h.asset_class, h.category, h.currency,
        \\       h.quantity, h.market_price, h.market_value, h.market_value_base, h.conid, h.synced_at
        \\FROM holdings h
        \\JOIN accounts a ON a.id = h.account_id
        \\WHERE h.market_value_base > 0.005
        \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
    , .{});
}

pub fn listAllocations(arena: std.mem.Allocator) ![]const Allocation {
    return try zx.db.rows(arena, Allocation,
        \\SELECT id, name, target_pct, sort_order, notes
        \\FROM allocations ORDER BY sort_order, name COLLATE NOCASE
    , .{});
}

pub fn getAccount(arena: std.mem.Allocator, id: i64) !?Account {
    return try zx.db.row(arena, Account,
        \\SELECT id, broker, external_id, name, currency, cash, net_liquidation, synced_at,
        \\       institution, account_type, asset_class, notes
        \\FROM accounts WHERE id = ?1
    , .{id});
}

pub fn snapshot(arena: std.mem.Allocator) !Snapshot {
    const accounts = try listAccountRows(arena);
    const holdings = try listHoldings(arena);
    const targets = try listAllocations(arena);

    var net_worth: f64 = 0;
    var cash_total: f64 = 0;
    for (accounts) |row| {
        net_worth += row.value_usd;
        const a = row.account;
        const is_cash_account = std.ascii.eqlIgnoreCase(a.account_type, "cash") or
            std.ascii.eqlIgnoreCase(a.asset_class, "Cash");
        cash_total += if (is_cash_account) row.value_usd else row.cash_usd;
    }
    const usd_bdt_rate = fx.usdBdtRate(arena);
    const aliases = try classAliases(arena);

    var class_value: std.StringHashMapUnmanaged(f64) = .empty;
    const classes = try listAssetClasses(arena);
    for (classes) |c| try class_value.put(arena, c.name, 0);

    for (accounts) |row| {
        const a = row.account;
        var from_holdings: f64 = 0;
        for (holdings) |h| {
            if (h.account_id != a.id) continue;
            from_holdings += h.market_value_base;
            const g = try class_value.getOrPutValue(arena, resolveClass(aliases, h.category), 0);
            g.value_ptr.* += h.market_value_base;
        }
        if (from_holdings > 0.005) {
            if (row.cash_usd > 0.005)
                (try class_value.getOrPutValue(arena, "Cash", 0)).value_ptr.* += row.cash_usd;
        } else {
            const cash = row.cash_usd;
            const rest = row.value_usd - cash;
            if (cash > 0.005)
                (try class_value.getOrPutValue(arena, "Cash", 0)).value_ptr.* += cash;
            if (rest > 0.005) {
                (try class_value.getOrPutValue(arena, resolveClass(aliases, a.asset_class), 0)).value_ptr.* += rest;
            } else if (cash < 0.005 and row.value_usd > 0.005) {
                (try class_value.getOrPutValue(arena, resolveClass(aliases, a.asset_class), 0)).value_ptr.* += row.value_usd;
            }
        }
    }

    var allocs: std.ArrayList(AllocationActual) = .empty;
    for (targets) |t| {
        const value = class_value.get(t.name) orelse 0;
        if (value <= 0.005) continue;
        try allocs.append(arena, .{
            .name = t.name,
            .target_pct = t.target_pct,
            .actual_value = value,
            .actual_pct = if (net_worth > 0) value / net_worth * 100.0 else 0,
            .sort_order = t.sort_order,
        });
    }
    var it = class_value.iterator();
    while (it.next()) |kv| {
        if (kv.value_ptr.* <= 0.005) continue;
        var known = false;
        for (allocs.items) |a| if (std.mem.eql(u8, a.name, kv.key_ptr.*)) {
            known = true;
            break;
        };
        if (known) continue;
        try allocs.append(arena, .{
            .name = kv.key_ptr.*,
            .target_pct = 0,
            .actual_value = kv.value_ptr.*,
            .actual_pct = if (net_worth > 0) kv.value_ptr.* / net_worth * 100.0 else 0,
            .sort_order = 99,
        });
    }

    var last_synced: ?[]const u8 = null;
    for (accounts) |row| {
        if (row.account.synced_at) |at| {
            if (last_synced == null or std.mem.order(u8, at, last_synced.?) == .gt) last_synced = at;
        }
    }

    return .{
        .net_worth = net_worth,
        .cash_total = cash_total,
        .invested_total = @max(0, net_worth - cash_total),
        .accounts = accounts,
        .holdings = holdings,
        .allocations = try allocs.toOwnedSlice(arena),
        .account_count = accounts.len,
        .holding_count = holdings.len,
        .last_synced = last_synced,
        .usd_bdt_rate = usd_bdt_rate,
        .net_worth_bdt = net_worth * usd_bdt_rate,
        .fx_as_of = fx.fetchedAt(arena),
    };
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

pub fn saveManualAccount(arena: std.mem.Allocator, input: struct {
    id: i64,
    name: []const u8,
    institution: []const u8,
    account_type: []const u8,
    asset_class: []const u8,
    currency: []const u8,
    balance: f64,
    notes: []const u8,
}) !void {
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
    const now = try nowSecs(arena);

    if (input.id == 0) {
        _ = try zx.db.run(
            \\INSERT INTO accounts
            \\  (broker, external_id, name, currency, cash, net_liquidation, institution,
            \\   account_type, asset_class, notes, synced_at)
            \\VALUES ('manual', ?1, ?2, ?3, 0, ?4, ?5, ?6, ?7, ?8, ?9)
        , .{
            try std.fmt.allocPrint(arena, "manual-{s}", .{now}),
            name,
            currency,
            input.balance,
            institution,
            input.account_type,
            input.asset_class,
            if (notes.len > 0) notes else null,
            now,
        });
        return;
    }

    _ = try zx.db.run(
        \\UPDATE accounts SET
        \\  name = ?1, institution = ?2, account_type = ?3, asset_class = ?4,
        \\  currency = ?5, net_liquidation = ?6, notes = ?7, synced_at = ?8
        \\WHERE id = ?9 AND broker = 'manual'
    , .{
        name,
        institution,
        input.account_type,
        input.asset_class,
        currency,
        input.balance,
        if (notes.len > 0) notes else null,
        now,
        input.id,
    });
}

pub fn deleteManualAccount(id: i64) !void {
    _ = try zx.db.run("DELETE FROM accounts WHERE id = ?1 AND broker = 'manual'", .{id});
}

pub fn setAccountAssetClass(arena: std.mem.Allocator, id: i64, asset_class: []const u8) !void {
    if (!try validAssetClass(arena, asset_class)) return error.InvalidName;
    _ = try zx.db.run("UPDATE accounts SET asset_class = ?1 WHERE id = ?2", .{ asset_class, id });
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
        try map.put(arena, try std.fmt.allocPrint(arena, "{s}\x00{s}", .{ row.external_id, row.symbol }), row.category);
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
        \\FROM accounts WHERE UPPER(currency) = 'XAU'
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
    return try std.fmt.allocPrint(arena, "{d}", .{std.Io.Timestamp.now(zx.io(), .real).toSeconds()});
}

pub fn formatMoney(arena: std.mem.Allocator, amount: f64, currency: []const u8) []const u8 {
    const abs = @abs(amount);
    const sign: []const u8 = if (amount < 0) "-" else "";
    if (fx.isMetal(currency)) {
        if (@abs(abs - @round(abs)) < 0.0005)
            return std.fmt.allocPrint(arena, "{s}{d} g", .{ sign, @as(i64, @intFromFloat(@round(abs))) }) catch "";
        return std.fmt.allocPrint(arena, "{s}{d:.2} g", .{ sign, abs }) catch "";
    }
    const whole: u64 = @intFromFloat(@floor(abs));
    var frac: u64 = @intFromFloat(@round((abs - @floor(abs)) * 100.0));
    if (frac >= 100) frac = 99;
    if (std.ascii.eqlIgnoreCase(currency, "BDT")) {
        if (frac == 0) return std.fmt.allocPrint(arena, "৳{s}{d}", .{ sign, whole }) catch "";
        return std.fmt.allocPrint(arena, "৳{s}{d}.{d:0>2}", .{ sign, whole, frac }) catch "";
    }
    if (std.ascii.eqlIgnoreCase(currency, "JPY"))
        return std.fmt.allocPrint(arena, "{s}¥{d}", .{ sign, whole }) catch "";
    return std.fmt.allocPrint(arena, "{s}{s} {d}.{d:0>2}", .{ sign, currency, whole, frac }) catch "";
}

pub fn formatPct(arena: std.mem.Allocator, pct: f64) []const u8 {
    const rounded: i64 = @intFromFloat(@round(pct * 10.0));
    return std.fmt.allocPrint(arena, "{d}.{d}%", .{ @divTrunc(rounded, 10), @mod(@abs(rounded), 10) }) catch "";
}

pub fn formatQty(arena: std.mem.Allocator, qty: f64) []const u8 {
    if (@abs(qty - @round(qty)) < 0.0001)
        return std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(@round(qty)))}) catch "";
    return std.fmt.allocPrint(arena, "{d:.4}", .{qty}) catch "";
}

pub fn accountTypeLabel(arena: std.mem.Allocator, t: []const u8) []const u8 {
    const row = zx.db.row(arena, struct { label: []const u8 },
        \\SELECT label FROM account_types WHERE id = ?1 LIMIT 1
    , .{t}) catch return t;
    return if (row) |r| r.label else t;
}

const std = @import("std");
const zx = @import("zx");

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
    cost_price: ?f64 = null,
    cost_basis_base: ?f64 = null,
    unrealized_pnl_base: ?f64 = null,
    exchange: []const u8 = "",
    weight_pct: f64 = 0,
};

pub const CashBalance = struct {
    account_id: i64,
    account_name: []const u8,
    currency: []const u8,
    amount: f64,
    settled: f64,
    amount_base: f64,
    weight_pct: f64 = 0,

    pub fn unsettled(self: CashBalance) f64 {
        const v = self.amount - self.settled;
        return if (@abs(v) < 0.005) 0 else v;
    }

    pub fn unsettledBase(self: CashBalance) f64 {
        if (@abs(self.amount) < 0.005) return 0;
        return self.unsettled() * self.amount_base / self.amount;
    }
};

// Largest first across active accounts; a null limit returns all.
pub fn list(arena: std.mem.Allocator, limit: ?usize) ![]const Holding {
    return try zx.db.rows(arena, Holding, holding_select ++
        \\WHERE h.market_value_base > 0.005 AND COALESCE(a.stale, 0) = 0
        \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
        \\LIMIT ?1
    , .{if (limit) |n| @as(i64, @intCast(n)) else -1});
}

pub fn forAccount(arena: std.mem.Allocator, account_id: i64) ![]const Holding {
    return try zx.db.rows(arena, Holding, holding_select ++
        \\WHERE h.account_id = ?1 AND h.market_value_base > 0.005
        \\ORDER BY h.market_value_base DESC, h.symbol COLLATE NOCASE
    , .{account_id});
}

pub fn cash(arena: std.mem.Allocator) ![]const CashBalance {
    return try zx.db.rows(arena, CashBalance, cash_select ++
        \\WHERE COALESCE(a.stale, 0) = 0 AND ABS(c.amount_base) > 0.005
        \\ORDER BY c.amount_base DESC, c.currency
    , .{});
}

pub fn cashForAccount(arena: std.mem.Allocator, account_id: i64) ![]const CashBalance {
    return try zx.db.rows(arena, CashBalance, cash_select ++
        \\WHERE c.account_id = ?1
        \\ORDER BY c.amount_base DESC, c.currency
    , .{account_id});
}

// Weights are against active assets, matching account weights.
const active_total_cte =
    \\WITH tot AS (
    \\  SELECT COALESCE(SUM(
    \\    CASE WHEN UPPER(a.currency) = 'USD' THEN a.net_liquidation
    \\         ELSE a.net_liquidation / COALESCE(NULLIF(fx.rate, 0), 1) END), 0) AS active_total
    \\  FROM accounts a
    \\  LEFT JOIN fx_rates fx ON fx.currency = UPPER(a.currency)
    \\  LEFT JOIN account_types t ON t.id = a.account_type
    \\  WHERE COALESCE(a.stale, 0) = 0 AND COALESCE(t.liability, 0) = 0
    \\)
    \\
;

const holding_select = active_total_cte ++
    \\SELECT h.id, h.account_id, a.name AS account_name, a.external_id AS account_external_id,
    \\       h.symbol, h.description, h.asset_class, h.category, h.currency,
    \\       h.quantity, h.market_price, h.market_value, h.market_value_base, h.conid, h.synced_at,
    \\       h.cost_price, h.cost_basis_base, h.unrealized_pnl_base, h.exchange,
    \\       CASE WHEN tot.active_total > 0 THEN h.market_value_base * 100.0 / tot.active_total
    \\            ELSE 0 END AS weight_pct
    \\FROM holdings h
    \\JOIN accounts a ON a.id = h.account_id
    \\CROSS JOIN tot
    \\
;

const cash_select = active_total_cte ++
    \\SELECT c.account_id, a.name AS account_name, c.currency, c.amount, c.settled, c.amount_base,
    \\       CASE WHEN tot.active_total > 0 THEN c.amount_base * 100.0 / tot.active_total
    \\            ELSE 0 END AS weight_pct
    \\FROM cash_balances c
    \\JOIN accounts a ON a.id = c.account_id
    \\CROSS JOIN tot
    \\
;

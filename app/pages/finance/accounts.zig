const std = @import("std");
const zx = @import("zx");
const classes = @import("classes.zig");
const fx = @import("fx.zig");

pub const Type = struct { id: []const u8, label: []const u8 };

pub fn types(arena: std.mem.Allocator) ![]const Type {
    return try zx.db.rows(arena, Type,
        \\SELECT id, label FROM account_types ORDER BY sort_order, id
    , .{});
}

pub const balance_stale_days = 30;

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

    pub fn isLiability(self: Account) bool {
        return self.liability != 0;
    }

    pub fn isStale(self: Account) bool {
        return self.stale != 0;
    }

    pub fn needsUpdate(self: Account, now: i64) bool {
        if (!std.mem.eql(u8, self.broker, "manual") or self.isStale()) return false;
        const at = std.fmt.parseInt(i64, self.synced_at orelse return true, 10) catch return true;
        return now - at > balance_stale_days * std.time.s_per_day;
    }
};

const Filter = union(enum) { active, everything, group: []const u8, id: i64 };

// Weights are against active assets; a single-account lookup also returns
// empty balances that listings hide.
fn query(arena: std.mem.Allocator, filter: Filter) ![]const Account {
    const id: i64 = if (filter == .id) filter.id else 0;
    const group: []const u8 = if (filter == .group) filter.group else "";
    const keep_empty: i64 = if (filter == .everything) 1 else 0;
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
        \\   AND (?3 != 0 OR ABS(v.value_usd) > 0.005 OR ABS(v.cash_usd) > 0.005 OR v.stale != 0) END
        \\ORDER BY CASE WHEN v.stale != 0 THEN 1 ELSE 0 END, v.value_usd DESC, v.name COLLATE NOCASE
    , .{ id, group, keep_empty });
}

pub fn list(arena: std.mem.Allocator) ![]const Account {
    return query(arena, .active);
}

// Includes empty accounts that `list` hides.
pub fn listAll(arena: std.mem.Allocator) ![]const Account {
    return query(arena, .everything);
}

pub fn listGroup(arena: std.mem.Allocator, group_name: []const u8) ![]const Account {
    return query(arena, .{ .group = group_name });
}

pub fn get(arena: std.mem.Allocator, id: i64) !?Account {
    const rows = try query(arena, .{ .id = id });
    return if (rows.len > 0) rows[0] else null;
}

pub const Entry = union(enum) {
    account: Account,
    group: Group,

    fn valueUsd(self: Entry) f64 {
        return switch (self) {
            .account => |a| if (a.isStale()) 0 else a.value_usd,
            .group => |g| g.value_usd,
        };
    }

    fn isStale(self: Entry) bool {
        return switch (self) {
            .account => |a| a.isStale(),
            .group => |g| g.stale_count == g.account_count,
        };
    }
};

// Totals cover active accounts only, like the portfolio totals.
pub const Group = struct {
    name: []const u8,
    value_usd: f64 = 0,
    weight_pct: f64 = 0,
    account_count: usize = 0,
    stale_count: usize = 0,
};

// Grouped accounts collapse into one entry per group; largest first, stale last.
pub fn entries(arena: std.mem.Allocator) ![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    for (try list(arena)) |a| {
        const name = a.group_name;
        if (name.len == 0) {
            try out.append(arena, .{ .account = a });
            continue;
        }
        const group = for (out.items) |*e| {
            if (e.* == .group and std.mem.eql(u8, e.group.name, name)) break &e.group;
        } else blk: {
            try out.append(arena, .{ .group = .{ .name = name } });
            break :blk &out.items[out.items.len - 1].group;
        };
        group.account_count += 1;
        if (a.isStale()) {
            group.stale_count += 1;
        } else {
            group.value_usd += a.value_usd;
            group.weight_pct += a.weight_pct;
        }
    }
    std.mem.sort(Entry, out.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.isStale() != b.isStale()) return b.isStale();
            return a.valueUsd() > b.valueUsd();
        }
    }.lessThan);
    return out.items;
}

pub const GroupSummary = struct { name: []const u8, account_count: i64 };

pub fn groups(arena: std.mem.Allocator) ![]const GroupSummary {
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
    , .{ from, trim(to) });
}

pub const Input = struct {
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
pub fn save(arena: std.mem.Allocator, io: std.Io, input: Input) !i64 {
    if (input.id != 0) {
        const existing = try get(arena, input.id) orelse return error.AccountMissing;
        if (!std.mem.eql(u8, existing.broker, "manual")) {
            if (!try classes.exists(arena, input.asset_class)) return error.InvalidName;
            const notes = trim(input.notes);
            _ = try zx.db.run(
                \\UPDATE accounts SET asset_class = ?1, group_name = ?2, notes = ?3, stale = ?4,
                \\  opened_at = unixepoch(NULLIF(?5, ''))
                \\WHERE id = ?6
            , .{
                input.asset_class,
                trim(input.group_name),
                if (notes.len > 0) notes else null,
                if (input.stale) @as(i64, 1) else 0,
                input.opened_on,
                input.id,
            });
            return input.id;
        }
    }
    return saveManual(arena, io, input);
}

fn saveManual(arena: std.mem.Allocator, io: std.Io, input: Input) !i64 {
    const name = trim(input.name);
    if (name.len == 0 or !try isType(arena, input.account_type) or !try classes.exists(arena, input.asset_class))
        return error.InvalidName;

    const institution = trim(input.institution);
    const currency = blk: {
        const c = trim(input.currency);
        const code = if (c.len > 0) c else "USD";
        if (!fx.isSupported(arena, code)) return error.InvalidName;
        break :blk try std.ascii.allocUpperString(arena, code);
    };
    const notes = trim(input.notes);
    const group_name = trim(input.group_name);
    const now = try timestamp(arena, io);
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

pub fn deleteManual(id: i64) !void {
    _ = try zx.db.run("DELETE FROM accounts WHERE id = ?1 AND broker = 'manual'", .{id});
}

pub fn setAssetClass(arena: std.mem.Allocator, id: i64, asset_class: []const u8) !void {
    if (!try classes.exists(arena, asset_class)) return error.InvalidName;
    _ = try zx.db.run("UPDATE accounts SET asset_class = ?1 WHERE id = ?2", .{ asset_class, id });
}

pub fn setStale(id: i64, stale: bool) !void {
    _ = try zx.db.run("UPDATE accounts SET stale = ?1 WHERE id = ?2", .{ if (stale) @as(i64, 1) else 0, id });
}

pub fn updateBalance(arena: std.mem.Allocator, io: std.Io, id: i64, balance: f64) !void {
    if (!std.math.isFinite(balance) or balance < 0) return error.InvalidAmount;
    const result = try zx.db.run(
        \\UPDATE accounts SET net_liquidation = ?1, synced_at = ?2
        \\WHERE id = ?3 AND broker = 'manual'
    , .{ balance, try timestamp(arena, io), id });
    if (result.changes == 0) return error.AccountMissing;
}

fn isType(arena: std.mem.Allocator, id: []const u8) !bool {
    const row = try zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM account_types WHERE id = ?1 LIMIT 1
    , .{id});
    return row != null;
}

// `synced_at` is stored as decimal Unix seconds text.
fn timestamp(arena: std.mem.Allocator, io: std.Io) ![]const u8 {
    return try arena.print("{d}", .{std.Io.Timestamp.now(io, .real).toSeconds()});
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

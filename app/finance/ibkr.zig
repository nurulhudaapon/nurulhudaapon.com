const std = @import("std");
const zx = @import("zx");
const xml = @import("xml");
const credentials = @import("../db/credentials.zig");
const classes = @import("classes.zig");
const history = @import("history.zig");

const log = std.log.scoped(.ibkr);

const send_url = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest";
const statement_url = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/GetStatement";

pub const Result = struct {
    accounts: usize,
    holdings: usize,
    cash_total: f64 = 0,
    saw_cash_report: bool = false,
    saw_equity_summary: bool = false,
};

pub fn sync(arena: std.mem.Allocator, io: std.Io) !Result {
    const creds = credentials.Ibkr.load(arena) orelse return error.NotConfigured;
    const flex: Flex = .{ .arena = arena, .io = io, .token = creds.token };
    const reference = try flex.send(creds.query_id);
    const body = try flex.statement(reference);
    var report = try Report.parse(arena, body);
    const synced_at = try arena.print("{d}", .{std.Io.Timestamp.now(io, .real).toSeconds()});
    return try report.store(arena, synced_at);
}

// Flex Web Service: SendRequest queues a statement, GetStatement polls for it.
const Flex = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    token: []const u8,

    fn send(f: Flex, query_id: []const u8) ![]const u8 {
        const url = try f.arena.print("{s}?t={s}&q={s}&v=3", .{ send_url, f.token, query_id });
        const body = try f.get(url);
        const meta = try Meta.parse(f.arena, body);
        if (!std.ascii.eqlIgnoreCase(meta.status orelse "", "Success")) {
            log.warn("SendRequest status={s} error={s}", .{ meta.status orelse "", meta.error_message orelse "" });
            return error.SendFailed;
        }
        return meta.reference orelse error.SendFailed;
    }

    fn statement(f: Flex, reference: []const u8) ![]const u8 {
        const url = try f.arena.print("{s}?t={s}&q={s}&v=3", .{ statement_url, f.token, reference });
        for (0..8) |attempt| {
            if (attempt > 0) f.io.sleep(.fromMilliseconds(800), .awake) catch {};
            const body = try f.get(url);
            if (containsElement(body, "FlexQueryResponse") or containsElement(body, "OpenPosition") or containsElement(body, "FlexStatement"))
                return body;

            const meta = Meta.parse(f.arena, body) catch continue;
            if (meta.status) |status| {
                // 1018: the statement is still being generated.
                if (std.ascii.eqlIgnoreCase(status, "Warn") and
                    std.mem.indexOf(u8, meta.error_code orelse "", "1018") != null)
                    continue;
                if (std.ascii.eqlIgnoreCase(status, "Fail") or std.ascii.eqlIgnoreCase(status, "Error")) {
                    log.warn("GetStatement status={s} error={s}", .{ status, meta.error_message orelse "" });
                    return error.StatementFailed;
                }
            }
        }
        return error.StatementPending;
    }

    fn get(f: Flex, url: []const u8) ![]const u8 {
        var client: zx.http.Client = .{ .io = f.io, .allocator = f.arena };
        defer client.deinit();
        const response = try client.fetch(.{
            .url = url,
            .headers = &.{.{ .name = "User-Agent", .value = "nurulhudaapon.com" }},
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(30_000), .clock = .awake } },
        });
        defer response.deinit(f.arena);
        if (response.status.class() != .success) {
            log.warn("GET failed status={d}", .{@backingInt(response.status)});
            return error.NetworkError;
        }
        return try f.arena.dupe(u8, response.body);
    }
};

const Meta = struct {
    status: ?[]const u8 = null,
    reference: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    error_code: ?[]const u8 = null,

    fn parse(arena: std.mem.Allocator, body: []const u8) !Meta {
        var parser: xml.Reader.Static = .init(arena, body, .{ .namespace_aware = false });
        defer parser.deinit();
        const reader = &parser.interface;

        var meta: Meta = .{};
        var current: ?[]const u8 = null;
        var text: std.ArrayList(u8) = .empty;

        while (true) {
            const node = reader.read() catch |err| switch (err) {
                error.MalformedXml => return meta,
                else => |e| return e,
            };
            switch (node) {
                .eof => break,
                .element_start => {
                    const name = reader.elementName();
                    if (eqlAny(name, &.{ "Status", "ReferenceCode", "ErrorMessage", "ErrorCode" })) {
                        current = try arena.dupe(u8, name);
                        text.clearRetainingCapacity();
                    } else current = null;
                },
                .text, .cdata => {
                    if (current == null) continue;
                    const chunk = if (node == .text) try reader.text() else try reader.cdata();
                    try text.appendSlice(arena, chunk);
                },
                .character_reference => {
                    if (current == null) continue;
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(reader.characterReferenceChar(), &buf) catch continue;
                    try text.appendSlice(arena, buf[0..len]);
                },
                .element_end => {
                    const name = current orelse continue;
                    const value = try arena.dupe(u8, std.mem.trim(u8, text.items, " \t\r\n"));
                    if (std.mem.eql(u8, name, "Status")) meta.status = value;
                    if (std.mem.eql(u8, name, "ReferenceCode")) meta.reference = value;
                    if (std.mem.eql(u8, name, "ErrorMessage")) meta.error_message = value;
                    if (std.mem.eql(u8, name, "ErrorCode")) meta.error_code = value;
                    current = null;
                    text.clearRetainingCapacity();
                },
                else => {},
            }
        }
        return meta;
    }
};

const Account = struct {
    external_id: []const u8,
    name: []const u8,
    currency: []const u8,
    settled_cash: ?f64 = null,
    settled_cash_sum: f64 = 0,
    equity_cash: ?f64 = null,
    net_liquidation: f64 = 0,
    nlv_from_equity: bool = false,
    opened_on: ?[]const u8 = null,
    // Daily NAV from dated equity summary rows; the newest also sets the fields above.
    history: std.ArrayList(history.DatedBalance) = .empty,
    equity_date: []const u8 = "",

    fn cash(self: Account) f64 {
        if (self.settled_cash) |v| {
            if (@abs(v) > 0.005) return v;
        }
        if (@abs(self.settled_cash_sum) > 0.005) return self.settled_cash_sum;
        if (self.equity_cash) |v| {
            if (@abs(v) > 0.005) return v;
        }
        return 0;
    }
};

const Position = struct {
    account_id: []const u8,
    symbol: []const u8,
    description: []const u8,
    asset_class: []const u8,
    currency: []const u8,
    quantity: f64,
    market_price: f64,
    market_value: f64,
    market_value_base: f64,
    conid: ?[]const u8,
    cost_price: ?f64,
    cost_basis_base: ?f64,
    unrealized_pnl_base: ?f64,
    exchange: []const u8,
};

const Cash = struct {
    account_id: []const u8,
    currency: []const u8,
    amount: f64,
    settled: f64,
    amount_base: f64,
};

const Report = struct {
    accounts: std.StringHashMapUnmanaged(Account) = .empty,
    holdings: std.ArrayList(Position) = .empty,
    cash: std.ArrayList(Cash) = .empty,
    saw_cash_report: bool = false,
    saw_equity_summary: bool = false,

    fn parse(arena: std.mem.Allocator, body: []const u8) !Report {
        var report: Report = .{};
        var parser: xml.Reader.Static = .init(arena, body, .{ .namespace_aware = false });
        defer parser.deinit();
        const reader = &parser.interface;

        while (true) {
            const node = reader.read() catch |err| switch (err) {
                error.MalformedXml => {
                    log.warn("malformed flex xml at {f}: {s}", .{ reader.errorLocation(), @tagName(reader.errorCode()) });
                    return error.EmptyReport;
                },
                else => |e| return e,
            };
            switch (node) {
                .eof => break,
                .element_start => {
                    const name = reader.elementName();
                    if (eqlAny(name, &.{ "FlexStatement", "AccountInformation" })) {
                        try report.addAccountInfo(arena, reader);
                    } else if (eqlAny(name, &.{ "EquitySummaryInBase", "EquitySummaryByReportDateInBase" })) {
                        report.saw_equity_summary = true;
                        try report.addEquity(arena, reader);
                    } else if (eqlAny(name, &.{ "CashReportCurrency", "CashReport" })) {
                        report.saw_cash_report = true;
                        try report.addCashReport(arena, reader);
                    } else if (std.mem.eql(u8, name, "OpenPosition")) {
                        try report.addPosition(arena, reader);
                    }
                },
                else => {},
            }
        }
        return report;
    }

    fn account(r: *Report, arena: std.mem.Allocator, id: []const u8) !*Account {
        const entry = try r.accounts.getOrPut(arena, id);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .external_id = id, .name = id, .currency = "USD" };
        }
        return entry.value_ptr;
    }

    fn addAccountInfo(r: *Report, arena: std.mem.Allocator, reader: *xml.Reader) !void {
        const account_id = try dupAttr(arena, reader, "accountId") orelse return;
        const entry = try r.account(arena, account_id);
        if (try dupAttr(arena, reader, "acctAlias")) |alias| {
            if (alias.len > 0) entry.name = alias;
        }
        if (try dupAttr(arena, reader, "currency")) |cur| {
            if (cur.len > 0) entry.currency = cur;
        }
        if (try isoDate(arena, attrRaw(reader, "dateOpened"))) |d| entry.opened_on = d;
    }

    fn addEquity(r: *Report, arena: std.mem.Allocator, reader: *xml.Reader) !void {
        const account_id = try dupAttr(arena, reader, "accountId") orelse return;
        const entry = try r.account(arena, account_id);
        const total = attrFloat(reader, "total");
        if (try isoDate(arena, attrRaw(reader, "reportDate"))) |date| {
            if (total) |t| try entry.history.append(arena, .{ .date = date, .balance = t });
            if (std.mem.order(u8, date, entry.equity_date) == .lt) return;
            entry.equity_date = date;
            entry.equity_cash = null;
        }
        if (total) |t| {
            entry.net_liquidation = t;
            entry.nlv_from_equity = true;
        }
        if (attrFloat(reader, "cash")) |v| entry.equity_cash = v;
        if (entry.equity_cash == null) {
            if (attrFloat(reader, "cashLong")) |v| entry.equity_cash = v;
        }
        if (entry.equity_cash == null) {
            if (attrFloat(reader, "brokerCash")) |v| entry.equity_cash = v;
        }
    }

    fn addCashReport(r: *Report, arena: std.mem.Allocator, reader: *xml.Reader) !void {
        const account_id = try dupAttr(arena, reader, "accountId") orelse return;
        if (attrRaw(reader, "levelOfDetail")) |lod| {
            if (std.ascii.eqlIgnoreCase(lod, "LOT") or std.ascii.eqlIgnoreCase(lod, "INTERNAL")) return;
        }
        const currency = try dupAttr(arena, reader, "currency") orelse return;
        const settled = firstAttrFloat(reader, &.{
            "endingSettledCash",
            "settledCash",
            "endingCash",
            "cashBalance",
            "startingCash",
        }) orelse return;

        const entry = try r.account(arena, account_id);
        const is_base = std.mem.eql(u8, currency, "BASE_SUMMARY") or std.ascii.eqlIgnoreCase(currency, "BASE");
        if (is_base) {
            if (@abs(settled) > 0.005) entry.settled_cash = settled;
            return;
        }
        const raw_rate = attrFloat(reader, "fxRateToBase") orelse 1;
        const rate = if (raw_rate == 0) 1 else raw_rate;
        const ending = attrFloat(reader, "endingCash") orelse settled;
        if (@abs(ending) >= 0.005 or @abs(settled) >= 0.005)
            try r.putCash(arena, .{
                .account_id = account_id,
                .currency = currency,
                .amount = ending,
                .settled = settled,
                .amount_base = ending * rate,
            });
        if (@abs(settled) < 0.005) return;

        entry.settled_cash_sum += settled * rate;
    }

    fn addPosition(r: *Report, arena: std.mem.Allocator, reader: *xml.Reader) !void {
        if (attrRaw(reader, "levelOfDetail")) |lod| {
            if (std.ascii.eqlIgnoreCase(lod, "LOT")) return;
        }
        const account_id = try dupAttr(arena, reader, "accountId") orelse return;
        const symbol = try dupAttr(arena, reader, "symbol") orelse return;
        const qty = attrFloat(reader, "position") orelse 0;
        if (qty == 0) return;

        const value = attrFloat(reader, "positionValue") orelse 0;
        const fx_rate = attrFloat(reader, "fxRateToBase") orelse 1;
        const value_base = attrFloat(reader, "positionValueInBase") orelse value * fx_rate;
        const asset_class = try dupAttr(arena, reader, "assetCategory") orelse "STK";

        const entry = try r.account(arena, account_id);
        if (std.ascii.eqlIgnoreCase(asset_class, "CASH") or std.ascii.eqlIgnoreCase(symbol, "CASH")) {
            if (@abs(value_base) > 0.005) entry.settled_cash_sum += value_base;
            const currency = try dupAttr(arena, reader, "currency") orelse symbol;
            if (@abs(value_base) > 0.005 and !r.hasCash(account_id, currency))
                try r.cash.append(arena, .{
                    .account_id = account_id,
                    .currency = currency,
                    .amount = value,
                    .settled = value,
                    .amount_base = value_base,
                });
            return;
        }

        try r.holdings.append(arena, .{
            .account_id = account_id,
            .symbol = symbol,
            .description = try dupAttr(arena, reader, "description") orelse symbol,
            .asset_class = asset_class,
            .currency = try dupAttr(arena, reader, "currency") orelse "USD",
            .quantity = qty,
            .market_price = attrFloat(reader, "markPrice") orelse 0,
            .market_value = value,
            .market_value_base = value_base,
            .conid = try dupAttr(arena, reader, "conid"),
            .cost_price = attrFloat(reader, "costBasisPrice"),
            .cost_basis_base = if (attrFloat(reader, "costBasisMoney")) |v| v * fx_rate else null,
            .unrealized_pnl_base = if (attrFloat(reader, "fifoPnlUnrealized")) |v| v * fx_rate else null,
            .exchange = try dupAttr(arena, reader, "listingExchange") orelse "",
        });
    }

    // The Cash Report wins over forex positions for the same currency.
    fn putCash(r: *Report, arena: std.mem.Allocator, row: Cash) !void {
        for (r.cash.items) |*c| {
            if (std.mem.eql(u8, c.account_id, row.account_id) and std.mem.eql(u8, c.currency, row.currency)) {
                c.* = row;
                return;
            }
        }
        try r.cash.append(arena, row);
    }

    fn hasCash(r: *const Report, account_id: []const u8, currency: []const u8) bool {
        for (r.cash.items) |c| {
            if (std.mem.eql(u8, c.account_id, account_id) and std.mem.eql(u8, c.currency, currency)) return true;
        }
        return false;
    }

    // Replaces all IBKR holdings and cash with this report, keeping user-set categories.
    fn store(r: *Report, arena: std.mem.Allocator, synced_at: []const u8) !Result {
        if (r.accounts.count() == 0 and r.holdings.items.len == 0) return error.EmptyReport;

        var cash_total: f64 = 0;
        var it = r.accounts.valueIterator();
        while (it.next()) |a| {
            var holdings_sum: f64 = 0;
            for (r.holdings.items) |h| {
                if (std.mem.eql(u8, h.account_id, a.external_id)) holdings_sum += h.market_value_base;
            }
            var cash = a.cash();
            if (a.nlv_from_equity) {
                const residual = a.net_liquidation - holdings_sum;
                if (residual > 0.005 and residual > cash + 0.005) {
                    cash = residual;
                    a.settled_cash = residual;
                } else if (@abs(cash) < 0.005 and residual > 0.005) {
                    cash = residual;
                    a.settled_cash = residual;
                }
            }
            if (!a.nlv_from_equity and a.net_liquidation == 0) {
                a.net_liquidation = cash + holdings_sum;
            } else if (a.nlv_from_equity and cash > 0.005) {
                const floor = cash + holdings_sum;
                if (a.net_liquidation + 0.005 < floor) a.net_liquidation = floor;
            }
            cash_total += cash;
        }

        const aliases = try classes.Aliases.load(arena);
        const overrides = try categoryOverrides(arena, aliases);
        try clearHoldings();

        var account_ids: std.StringHashMapUnmanaged(i64) = .empty;
        var acc_it = r.accounts.valueIterator();
        while (acc_it.next()) |a| {
            const id = try upsertAccount(arena, a.*, synced_at);
            try account_ids.put(arena, a.external_id, id);
            try history.importBalances(id, a.opened_on, a.history.items);
        }

        for (r.holdings.items) |h| {
            const account_id = account_ids.get(h.account_id) orelse continue;
            const key = try arena.print("{s}\x00{s}", .{ h.account_id, h.symbol });
            try insertHolding(account_id, h, overrides.get(key) orelse aliases.resolve(h.asset_class), synced_at);
        }

        for (r.cash.items) |c| {
            const account_id = account_ids.get(c.account_id) orelse continue;
            try insertCash(account_id, c, synced_at);
        }

        if (!r.saw_cash_report and !r.saw_equity_summary) {
            log.warn("Flex XML had no CashReport or EquitySummary - enable both in the Flex Query to capture cash", .{});
        } else if (cash_total < 0.005) {
            log.info("synced with cash≈0 (cash_report={any} equity_summary={any})", .{ r.saw_cash_report, r.saw_equity_summary });
        }

        return .{
            .accounts = r.accounts.count(),
            .holdings = r.holdings.items.len,
            .cash_total = cash_total,
            .saw_cash_report = r.saw_cash_report,
            .saw_equity_summary = r.saw_equity_summary,
        };
    }
};

fn upsertAccount(arena: std.mem.Allocator, a: Account, synced_at: []const u8) !i64 {
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
    , .{ a.external_id, a.name, a.currency, a.cash(), a.net_liquidation, synced_at });

    const row = try zx.db.row(arena, struct { id: i64 },
        \\SELECT id FROM accounts WHERE broker = 'ibkr' AND external_id = ?1
    , .{a.external_id}) orelse return error.AccountMissing;
    return row.id;
}

fn clearHoldings() !void {
    _ = try zx.db.run(
        \\DELETE FROM holdings
        \\WHERE account_id IN (SELECT id FROM accounts WHERE broker = 'ibkr')
    , .{});
    _ = try zx.db.run(
        \\DELETE FROM cash_balances
        \\WHERE account_id IN (SELECT id FROM accounts WHERE broker = 'ibkr')
    , .{});
}

fn insertCash(account_id: i64, c: Cash, synced_at: []const u8) !void {
    _ = try zx.db.run(
        \\INSERT INTO cash_balances (account_id, currency, amount, settled, amount_base, synced_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        \\ON CONFLICT (account_id, currency) DO UPDATE SET
        \\  amount = excluded.amount,
        \\  settled = excluded.settled,
        \\  amount_base = excluded.amount_base,
        \\  synced_at = excluded.synced_at
    , .{ account_id, c.currency, c.amount, c.settled, c.amount_base, synced_at });
}

fn insertHolding(account_id: i64, h: Position, category: []const u8, synced_at: []const u8) !void {
    _ = try zx.db.run(
        \\INSERT INTO holdings
        \\  (account_id, symbol, description, asset_class, category, currency,
        \\   quantity, market_price, market_value, market_value_base, conid, synced_at,
        \\   cost_price, cost_basis_base, unrealized_pnl_base, exchange)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
    , .{
        account_id,
        h.symbol,
        h.description,
        h.asset_class,
        category,
        h.currency,
        h.quantity,
        h.market_price,
        h.market_value,
        h.market_value_base,
        h.conid,
        synced_at,
        h.cost_price,
        h.cost_basis_base,
        h.unrealized_pnl_base,
        h.exchange,
    });
}

// Categories the user changed from the alias default, keyed by "external_id\x00symbol".
fn categoryOverrides(arena: std.mem.Allocator, aliases: classes.Aliases) !std.StringHashMapUnmanaged([]const u8) {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
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
        if (std.mem.eql(u8, row.category, aliases.resolve(row.asset_class))) continue;
        try map.put(arena, try arena.print("{s}\x00{s}", .{ row.external_id, row.symbol }), row.category);
    }
    return map;
}

// Flex dates come as yyyyMMdd or yyyy-MM-dd depending on the query settings.
fn isoDate(arena: std.mem.Allocator, raw: ?[]const u8) !?[]const u8 {
    const d = raw orelse return null;
    if (d.len == 10 and d[4] == '-') return try arena.dupe(u8, d);
    if (d.len == 8) return try arena.print("{s}-{s}-{s}", .{ d[0..4], d[4..6], d[6..8] });
    return null;
}

fn containsElement(body: []const u8, name: []const u8) bool {
    var needle_buf: [64]u8 = undefined;
    if (name.len + 1 > needle_buf.len) return std.mem.indexOf(u8, body, name) != null;
    needle_buf[0] = '<';
    @memcpy(needle_buf[1 .. 1 + name.len], name);
    return std.mem.indexOf(u8, body, needle_buf[0 .. 1 + name.len]) != null;
}

fn attrRaw(reader: *xml.Reader, name: []const u8) ?[]const u8 {
    const i = reader.attributeIndex(name) orelse return null;
    return reader.attributeValueRaw(i);
}

fn dupAttr(arena: std.mem.Allocator, reader: *xml.Reader, name: []const u8) !?[]const u8 {
    const raw = attrRaw(reader, name) orelse return null;
    return try arena.dupe(u8, raw);
}

fn attrFloat(reader: *xml.Reader, name: []const u8) ?f64 {
    const raw = attrRaw(reader, name) orelse return null;
    return std.fmt.parseFloat(f64, raw) catch null;
}

fn firstAttrFloat(reader: *xml.Reader, names: []const []const u8) ?f64 {
    for (names) |name| {
        if (attrFloat(reader, name)) |v| return v;
    }
    return null;
}

fn eqlAny(value: []const u8, options: []const []const u8) bool {
    for (options) |opt| if (std.mem.eql(u8, value, opt)) return true;
    return false;
}

test "parse flex meta and report cash" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const meta = try Meta.parse(arena,
        \\<?xml version="1.0"?>
        \\<FlexStatementResponse>
        \\  <Status>Success</Status>
        \\  <ReferenceCode>123456</ReferenceCode>
        \\</FlexStatementResponse>
    );
    try std.testing.expectEqualStrings("Success", meta.status.?);
    try std.testing.expectEqualStrings("123456", meta.reference.?);

    const parsed = try Report.parse(arena,
        \\<?xml version="1.0"?>
        \\<FlexQueryResponse>
        \\  <FlexStatement accountId="U1">
        \\    <EquitySummaryInBase accountId="U1" total="2000" cash="250" />
        \\    <CashReportCurrency accountId="U1" currency="BASE_SUMMARY" endingCash="250" endingSettledCash="195" />
        \\    <OpenPosition accountId="U1" assetCategory="STK" currency="USD" symbol="AAPL" description="APPLE INC" conid="265598" position="10" markPrice="180.5" positionValue="1805" fxRateToBase="1" levelOfDetail="SUMMARY" />
        \\  </FlexStatement>
        \\</FlexQueryResponse>
    );
    try std.testing.expectEqual(@as(usize, 1), parsed.accounts.count());
    try std.testing.expectEqual(@as(usize, 1), parsed.holdings.items.len);
    const acc = parsed.accounts.get("U1").?;
    try std.testing.expectEqual(@as(f64, 195), acc.cash());
    try std.testing.expectEqual(@as(f64, 2000), acc.net_liquidation);
    try std.testing.expectEqualStrings("AAPL", parsed.holdings.items[0].symbol);
    try std.testing.expectEqual(@as(?f64, null), parsed.holdings.items[0].cost_basis_base);
    try std.testing.expectEqual(@as(usize, 0), parsed.cash.items.len);

    const parsed2 = try Report.parse(arena,
        \\<?xml version="1.0"?>
        \\<FlexQueryResponse>
        \\  <FlexStatement accountId="U2">
        \\    <EquitySummaryInBase accountId="U2" total="1100" cash="100" />
        \\    <CashReportCurrency accountId="U2" currency="BASE_SUMMARY" endingSettledCash="0" />
        \\    <CashReportCurrency accountId="U2" currency="USD" endingSettledCash="100" fxRateToBase="1" />
        \\    <OpenPosition accountId="U2" assetCategory="STK" currency="USD" symbol="SPY" position="1" positionValue="1000" fxRateToBase="1" levelOfDetail="SUMMARY" />
        \\  </FlexStatement>
        \\</FlexQueryResponse>
    );
    try std.testing.expectEqual(@as(f64, 100), parsed2.accounts.get("U2").?.cash());

    const parsed4 = try Report.parse(arena,
        \\<?xml version="1.0"?>
        \\<FlexQueryResponse>
        \\  <FlexStatement accountId="U4">
        \\    <CashReportCurrency accountId="U4" currency="USD" endingCash="500" endingSettledCash="300" fxRateToBase="1" />
        \\    <CashReportCurrency accountId="U4" currency="EUR" endingCash="100" endingSettledCash="100" fxRateToBase="1.1" />
        \\    <OpenPosition accountId="U4" assetCategory="CASH" currency="EUR" symbol="EUR.USD" position="100" positionValue="100" fxRateToBase="1.1" levelOfDetail="SUMMARY" />
        \\    <OpenPosition accountId="U4" assetCategory="STK" currency="EUR" symbol="SAP" listingExchange="IBIS" position="2" markPrice="200" positionValue="400" costBasisPrice="150" costBasisMoney="300" fifoPnlUnrealized="100" fxRateToBase="1.1" levelOfDetail="SUMMARY" />
        \\  </FlexStatement>
        \\</FlexQueryResponse>
    );
    try std.testing.expectEqual(@as(usize, 2), parsed4.cash.items.len);
    const usd = parsed4.cash.items[0];
    try std.testing.expectEqualStrings("USD", usd.currency);
    try std.testing.expectEqual(@as(f64, 500), usd.amount);
    try std.testing.expectEqual(@as(f64, 300), usd.settled);
    try std.testing.expectApproxEqAbs(@as(f64, 110), parsed4.cash.items[1].amount_base, 1e-9);
    const sap = parsed4.holdings.items[0];
    try std.testing.expectEqual(@as(?f64, 150), sap.cost_price);
    try std.testing.expectApproxEqAbs(@as(f64, 330), sap.cost_basis_base.?, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 110), sap.unrealized_pnl_base.?, 1e-9);
    try std.testing.expectEqualStrings("IBIS", sap.exchange);

    const parsed3 = try Report.parse(arena,
        \\<?xml version="1.0"?>
        \\<FlexQueryResponse>
        \\  <FlexStatement accountId="U3">
        \\    <AccountInformation accountId="U3" currency="USD" dateOpened="20230115" />
        \\    <EquitySummaryByReportDateInBase accountId="U3" reportDate="20261026" total="1200" cash="50" />
        \\    <EquitySummaryByReportDateInBase accountId="U3" reportDate="20261020" total="1000" cash="10" />
        \\  </FlexStatement>
        \\</FlexQueryResponse>
    );
    const acc3 = parsed3.accounts.get("U3").?;
    try std.testing.expectEqualStrings("2023-01-15", acc3.opened_on.?);
    try std.testing.expectEqual(@as(usize, 2), acc3.history.items.len);
    try std.testing.expectEqual(@as(f64, 1200), acc3.net_liquidation);
    try std.testing.expectEqual(@as(?f64, 50), acc3.equity_cash);
}

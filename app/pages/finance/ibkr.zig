const std = @import("std");
const zx = @import("zx");
const xml = @import("xml");
const credentials = @import("../../db/credentials.zig");
const db = @import("db.zig");

const send_url = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest";
const statement_url = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/GetStatement";

pub const Result = struct {
    accounts: usize,
    holdings: usize,
    cash_total: f64 = 0,
    saw_cash_report: bool = false,
    saw_equity_summary: bool = false,
};

pub const sync_cache_secs: i64 = 10 * 60;

pub fn sync(arena: std.mem.Allocator) !Result {
    const creds = credentials.loadIbkr(arena) orelse return error.NotConfigured;
    const reference = try sendRequest(arena, creds.token, creds.query_id);
    const body = try getStatement(arena, creds.token, reference);
    return try applyReport(arena, body);
}

pub fn syncIfStale(arena: std.mem.Allocator) !?Result {
    if (credentials.loadIbkr(arena) == null) return null;
    if (lastSyncedSecs(arena)) |at| {
        const now = std.Io.Timestamp.now(zx.io(), .real).toSeconds();
        if (now - at < sync_cache_secs) return null;
    }
    return try sync(arena);
}

fn lastSyncedSecs(arena: std.mem.Allocator) ?i64 {
    const row = zx.db.row(arena, struct { synced_at: ?[]const u8 },
        \\SELECT MAX(synced_at) AS synced_at FROM accounts WHERE broker = 'ibkr'
    , .{}) catch return null;
    const raw = if (row) |r| r.synced_at else null;
    const s = raw orelse return null;
    return std.fmt.parseInt(i64, s, 10) catch null;
}

fn sendRequest(arena: std.mem.Allocator, token: []const u8, query_id: []const u8) ![]const u8 {
    const url = try arena.print("{s}?t={s}&q={s}&v=3", .{ send_url, token, query_id });
    const body = try fetchText(arena, url);
    const meta = try parseFlexMeta(arena, body);
    if (!std.ascii.eqlIgnoreCase(meta.status orelse "", "Success")) {
        zx.log.warn("ibkr: SendRequest status={s} error={s}", .{ meta.status orelse "", meta.error_message orelse "" });
        return error.SendFailed;
    }
    return meta.reference orelse error.SendFailed;
}

fn getStatement(arena: std.mem.Allocator, token: []const u8, reference: []const u8) ![]const u8 {
    const url = try arena.print("{s}?t={s}&q={s}&v=3", .{ statement_url, token, reference });
    var attempt: usize = 0;
    while (attempt < 8) : (attempt += 1) {
        if (attempt > 0) zx.io().sleep(.fromMilliseconds(800), .awake) catch {};
        const body = try fetchText(arena, url);
        if (containsElement(body, "FlexQueryResponse") or containsElement(body, "OpenPosition") or containsElement(body, "FlexStatement"))
            return body;

        const meta = parseFlexMeta(arena, body) catch continue;
        if (meta.status) |status| {
            if (std.ascii.eqlIgnoreCase(status, "Warn") and
                std.mem.indexOf(u8, meta.error_code orelse "", "1018") != null)
                continue;
            if (std.ascii.eqlIgnoreCase(status, "Fail") or std.ascii.eqlIgnoreCase(status, "Error")) {
                zx.log.warn("ibkr: GetStatement status={s} error={s}", .{ status, meta.error_message orelse "" });
                return error.StatementFailed;
            }
        }
    }
    return error.StatementPending;
}

fn fetchText(arena: std.mem.Allocator, url: []const u8) ![]const u8 {
    var response = (try zx.fetch(.blocking, arena, url, .{
        .headers = &.{.{ .name = "User-Agent", .value = "nurulhudaapon.com" }},
        .timeout_ms = 30_000,
    })) orelse return error.NetworkError;
    defer response.deinit();
    if (!response.ok()) {
        zx.log.warn("ibkr: GET failed status={d}", .{response.status});
        return error.NetworkError;
    }
    return try arena.dupe(u8, try response.text());
}

const AccountAcc = struct {
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
    history: std.ArrayList(db.DatedBalance) = .empty,
    equity_date: []const u8 = "",

    fn cash(self: AccountAcc) f64 {
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

const HoldingAcc = struct {
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
};

const ParsedReport = struct {
    accounts: std.StringHashMapUnmanaged(AccountAcc),
    holdings: std.ArrayList(HoldingAcc),
    saw_cash_report: bool = false,
    saw_equity_summary: bool = false,
};

const FlexMeta = struct {
    status: ?[]const u8 = null,
    reference: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    error_code: ?[]const u8 = null,
};

fn applyReport(arena: std.mem.Allocator, body: []const u8) !Result {
    var parsed = try parseReport(arena, body);
    if (parsed.accounts.count() == 0 and parsed.holdings.items.len == 0) return error.EmptyReport;

    var cash_total: f64 = 0;
    var it = parsed.accounts.iterator();
    while (it.next()) |kv| {
        var holdings_sum: f64 = 0;
        for (parsed.holdings.items) |h| {
            if (std.mem.eql(u8, h.account_id, kv.key_ptr.*)) holdings_sum += h.market_value_base;
        }
        var cash = kv.value_ptr.*.cash();
        if (kv.value_ptr.*.nlv_from_equity) {
            const residual = kv.value_ptr.*.net_liquidation - holdings_sum;
            if (residual > 0.005 and residual > cash + 0.005) {
                cash = residual;
                kv.value_ptr.*.settled_cash = residual;
            } else if (@abs(cash) < 0.005 and residual > 0.005) {
                cash = residual;
                kv.value_ptr.*.settled_cash = residual;
            }
        }
        if (!kv.value_ptr.*.nlv_from_equity and kv.value_ptr.*.net_liquidation == 0) {
            kv.value_ptr.*.net_liquidation = cash + holdings_sum;
        } else if (kv.value_ptr.*.nlv_from_equity and cash > 0.005) {
            const floor = cash + holdings_sum;
            if (kv.value_ptr.*.net_liquidation + 0.005 < floor)
                kv.value_ptr.*.net_liquidation = floor;
        }
        cash_total += cash;
    }

    const synced_at = try nowSecs(arena);
    const aliases = try db.classAliases(arena);
    var overrides = try db.categoryOverrides(arena);
    try db.clearIbkrHoldings();

    var account_ids: std.StringHashMapUnmanaged(i64) = .empty;
    var acc_it = parsed.accounts.iterator();
    var account_count: usize = 0;
    while (acc_it.next()) |kv| {
        const a = kv.value_ptr.*;
        const cash = a.cash();
        const id = try db.upsertAccount(arena, .{
            .external_id = a.external_id,
            .name = a.name,
            .currency = a.currency,
            .cash = cash,
            .net_liquidation = a.net_liquidation,
            .synced_at = synced_at,
        });
        try account_ids.put(arena, a.external_id, id);
        try db.importHistory(id, a.opened_on, a.history.items);
        account_count += 1;
    }

    for (parsed.holdings.items) |h| {
        const account_id = account_ids.get(h.account_id) orelse continue;
        const key = try arena.print("{s}\x00{s}", .{ h.account_id, h.symbol });
        try db.insertHolding(.{
            .account_id = account_id,
            .symbol = h.symbol,
            .description = h.description,
            .asset_class = h.asset_class,
            .category = overrides.get(key) orelse db.categoryForAssetClass(aliases, h.asset_class),
            .currency = h.currency,
            .quantity = h.quantity,
            .market_price = h.market_price,
            .market_value = h.market_value,
            .market_value_base = h.market_value_base,
            .conid = h.conid,
            .synced_at = synced_at,
        });
    }

    if (!parsed.saw_cash_report and !parsed.saw_equity_summary) {
        zx.log.warn("ibkr: Flex XML had no CashReport or EquitySummary - enable both in the Flex Query to capture cash", .{});
    } else if (cash_total < 0.005) {
        zx.log.info("ibkr: synced with cash≈0 (cash_report={any} equity_summary={any})", .{ parsed.saw_cash_report, parsed.saw_equity_summary });
    }

    return .{
        .accounts = account_count,
        .holdings = parsed.holdings.items.len,
        .cash_total = cash_total,
        .saw_cash_report = parsed.saw_cash_report,
        .saw_equity_summary = parsed.saw_equity_summary,
    };
}

fn parseReport(arena: std.mem.Allocator, body: []const u8) !ParsedReport {
    var accounts: std.StringHashMapUnmanaged(AccountAcc) = .empty;
    var holdings: std.ArrayList(HoldingAcc) = .empty;
    var saw_cash_report = false;
    var saw_equity_summary = false;

    var parser: xml.Reader.Static = .init(arena, body, .{ .namespace_aware = false });
    defer parser.deinit();
    const reader = &parser.interface;

    while (true) {
        const node = reader.read() catch |err| switch (err) {
            error.MalformedXml => {
                zx.log.warn("ibkr: malformed flex xml at {f}: {s}", .{ reader.errorLocation(), @tagName(reader.errorCode()) });
                return error.EmptyReport;
            },
            else => |e| return e,
        };
        switch (node) {
            .eof => break,
            .element_start => {
                const name = reader.elementName();
                if (eqlAny(name, &.{ "FlexStatement", "AccountInformation" })) {
                    try ingestAccountInfo(arena, &accounts, reader);
                } else if (eqlAny(name, &.{ "EquitySummaryInBase", "EquitySummaryByReportDateInBase" })) {
                    saw_equity_summary = true;
                    try ingestEquity(arena, &accounts, reader);
                } else if (eqlAny(name, &.{ "CashReportCurrency", "CashReport" })) {
                    saw_cash_report = true;
                    try ingestCashReport(arena, &accounts, reader);
                } else if (std.mem.eql(u8, name, "OpenPosition")) {
                    try ingestPosition(arena, &accounts, &holdings, reader);
                }
            },
            else => {},
        }
    }

    return .{
        .accounts = accounts,
        .holdings = holdings,
        .saw_cash_report = saw_cash_report,
        .saw_equity_summary = saw_equity_summary,
    };
}

fn ingestAccountInfo(arena: std.mem.Allocator, accounts: *std.StringHashMapUnmanaged(AccountAcc), reader: *xml.Reader) !void {
    const account_id = try dupAttr(arena, reader, "accountId") orelse return;
    const entry = try ensureAccount(accounts, arena, account_id);
    if (try dupAttr(arena, reader, "acctAlias")) |alias| {
        if (alias.len > 0) entry.*.name = alias;
    }
    if (try dupAttr(arena, reader, "currency")) |cur| {
        if (cur.len > 0) entry.*.currency = cur;
    }
    if (try isoDate(arena, attrRaw(reader, "dateOpened"))) |d| entry.*.opened_on = d;
}

// Flex dates come as yyyyMMdd or yyyy-MM-dd depending on the query settings.
fn isoDate(arena: std.mem.Allocator, raw: ?[]const u8) !?[]const u8 {
    const d = raw orelse return null;
    if (d.len == 10 and d[4] == '-') return try arena.dupe(u8, d);
    if (d.len == 8) return try arena.print("{s}-{s}-{s}", .{ d[0..4], d[4..6], d[6..8] });
    return null;
}

fn ingestEquity(arena: std.mem.Allocator, accounts: *std.StringHashMapUnmanaged(AccountAcc), reader: *xml.Reader) !void {
    const account_id = try dupAttr(arena, reader, "accountId") orelse return;
    const entry = try ensureAccount(accounts, arena, account_id);
    const total = attrFloat(reader, "total");
    if (try isoDate(arena, attrRaw(reader, "reportDate"))) |date| {
        if (total) |t| try entry.*.history.append(arena, .{ .date = date, .balance = t });
        if (std.mem.order(u8, date, entry.*.equity_date) == .lt) return;
        entry.*.equity_date = date;
        entry.*.equity_cash = null;
    }
    if (total) |t| {
        entry.*.net_liquidation = t;
        entry.*.nlv_from_equity = true;
    }
    if (attrFloat(reader, "cash")) |cash| entry.*.equity_cash = cash;
    if (entry.*.equity_cash == null) {
        if (attrFloat(reader, "cashLong")) |cash| entry.*.equity_cash = cash;
    }
    if (entry.*.equity_cash == null) {
        if (attrFloat(reader, "brokerCash")) |cash| entry.*.equity_cash = cash;
    }
}

fn ingestCashReport(arena: std.mem.Allocator, accounts: *std.StringHashMapUnmanaged(AccountAcc), reader: *xml.Reader) !void {
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

    const entry = try ensureAccount(accounts, arena, account_id);
    const is_base = std.mem.eql(u8, currency, "BASE_SUMMARY") or std.ascii.eqlIgnoreCase(currency, "BASE");
    if (is_base) {
        if (@abs(settled) > 0.005) entry.*.settled_cash = settled;
        return;
    }
    if (@abs(settled) < 0.005) return;

    const rate = attrFloat(reader, "fxRateToBase") orelse 1;
    entry.*.settled_cash_sum += settled * (if (rate == 0) 1 else rate);
}

fn ingestPosition(
    arena: std.mem.Allocator,
    accounts: *std.StringHashMapUnmanaged(AccountAcc),
    holdings: *std.ArrayList(HoldingAcc),
    reader: *xml.Reader,
) !void {
    if (attrRaw(reader, "levelOfDetail")) |lod| {
        if (std.ascii.eqlIgnoreCase(lod, "LOT")) return;
    }
    const account_id = try dupAttr(arena, reader, "accountId") orelse return;
    const symbol = try dupAttr(arena, reader, "symbol") orelse return;
    const qty = attrFloat(reader, "position") orelse 0;
    if (qty == 0) return;

    const value = attrFloat(reader, "positionValue") orelse 0;
    const fx = attrFloat(reader, "fxRateToBase") orelse 1;
    const value_base = attrFloat(reader, "positionValueInBase") orelse value * fx;
    const asset_class = try dupAttr(arena, reader, "assetCategory") orelse "STK";

    const entry = try ensureAccount(accounts, arena, account_id);
    if (std.ascii.eqlIgnoreCase(asset_class, "CASH") or std.ascii.eqlIgnoreCase(symbol, "CASH")) {
        if (@abs(value_base) > 0.005) entry.*.settled_cash_sum += value_base;
        return;
    }

    try holdings.append(arena, .{
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
    });
}

fn ensureAccount(accounts: *std.StringHashMapUnmanaged(AccountAcc), arena: std.mem.Allocator, account_id: []const u8) !*AccountAcc {
    const entry = try accounts.getOrPut(arena, account_id);
    if (!entry.found_existing) {
        entry.value_ptr.* = .{ .external_id = account_id, .name = account_id, .currency = "USD" };
    }
    return entry.value_ptr;
}

fn parseFlexMeta(arena: std.mem.Allocator, body: []const u8) !FlexMeta {
    var parser: xml.Reader.Static = .init(arena, body, .{ .namespace_aware = false });
    defer parser.deinit();
    const reader = &parser.interface;

    var meta: FlexMeta = .{};
    var current: ?[]const u8 = null;
    var text_buf: std.ArrayList(u8) = .empty;

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
                    text_buf.clearRetainingCapacity();
                } else current = null;
            },
            .text, .cdata => {
                if (current == null) continue;
                const chunk = if (node == .text) try reader.text() else try reader.cdata();
                try text_buf.appendSlice(arena, chunk);
            },
            .character_reference => {
                if (current == null) continue;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(reader.characterReferenceChar(), &buf) catch continue;
                try text_buf.appendSlice(arena, buf[0..len]);
            },
            .element_end => {
                const name = current orelse continue;
                const value = try arena.dupe(u8, std.mem.trim(u8, text_buf.items, " \t\r\n"));
                if (std.mem.eql(u8, name, "Status")) meta.status = value;
                if (std.mem.eql(u8, name, "ReferenceCode")) meta.reference = value;
                if (std.mem.eql(u8, name, "ErrorMessage")) meta.error_message = value;
                if (std.mem.eql(u8, name, "ErrorCode")) meta.error_code = value;
                current = null;
                text_buf.clearRetainingCapacity();
            },
            else => {},
        }
    }
    return meta;
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

fn nowSecs(arena: std.mem.Allocator) ![]const u8 {
    return try arena.print("{d}", .{std.Io.Timestamp.now(zx.io(), .real).toSeconds()});
}

test "parse flex meta and report cash" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const meta = try parseFlexMeta(arena,
        \\<?xml version="1.0"?>
        \\<FlexStatementResponse>
        \\  <Status>Success</Status>
        \\  <ReferenceCode>123456</ReferenceCode>
        \\</FlexStatementResponse>
    );
    try std.testing.expectEqualStrings("Success", meta.status.?);
    try std.testing.expectEqualStrings("123456", meta.reference.?);

    var parsed = try parseReport(arena,
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

    var parsed2 = try parseReport(arena,
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

    var parsed3 = try parseReport(arena,
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

const std = @import("std");
const zx = @import("zx");

const rates_url = "https://api.frankfurter.dev/v2/rates?base=usd";
const bajus_url = "https://www.bajus.org/gold-price";
const cache_ttl_secs: i64 = 12 * 60 * 60;
const bajus_22k_haircut: f64 = 0.85;

pub const Rate = struct {
    currency: []const u8,
    rate: f64,
    as_of: []const u8,
    fetched_at: i64,
};

pub fn refresh(arena: std.mem.Allocator) void {
    if (!cacheFresh(arena, false)) _ = fetchFiat(arena);
    if (!cacheFresh(arena, true)) _ = fetchBajusGold(arena);
}

pub fn syncNow(arena: std.mem.Allocator) !void {
    const fiat_ok = fetchFiat(arena);
    const gold_ok = fetchBajusGold(arena);
    if (!fiat_ok and !gold_ok) return error.FetchFailed;
}

pub fn listRates(arena: std.mem.Allocator) ![]const Rate {
    refresh(arena);
    return try zx.db.rows(arena, Rate,
        \\SELECT currency, rate, as_of, fetched_at FROM fx_rates
        \\ORDER BY
        \\  CASE currency
        \\    WHEN 'USD' THEN 0 WHEN 'BDT' THEN 1 WHEN 'XAU' THEN 2 WHEN 'XAG' THEN 3
        \\    ELSE 4 END,
        \\  currency
    , .{});
}

pub fn listCurrencies(arena: std.mem.Allocator) ![]const []const u8 {
    const rates = try listRates(arena);
    const out = try arena.alloc([]const u8, rates.len);
    for (rates, 0..) |r, i| out[i] = r.currency;
    return out;
}

pub fn usdBdtRate(arena: std.mem.Allocator) f64 {
    const row = zx.db.row(arena, struct { rate: f64 },
        \\SELECT rate FROM fx_rates WHERE currency = 'BDT' LIMIT 1
    , .{}) catch return 122;
    return if (row) |r| if (r.rate > 0) r.rate else 122 else 122;
}

pub fn fetchedAt(arena: std.mem.Allocator) ?i64 {
    const row = zx.db.row(arena, struct { fetched_at: i64 },
        \\SELECT MAX(fetched_at) AS fetched_at FROM fx_rates
        \\WHERE fetched_at > 0 AND as_of NOT IN ('seed', '')
    , .{}) catch return null;
    const at = if (row) |r| r.fetched_at else 0;
    return if (at > 0) at else null;
}

pub fn isSupported(arena: std.mem.Allocator, currency: []const u8) bool {
    const row = zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM fx_rates WHERE currency = UPPER(?1) LIMIT 1
    , .{currency}) catch return std.ascii.eqlIgnoreCase(currency, "USD");
    return row != null;
}

pub fn isMetal(currency: []const u8) bool {
    return std.ascii.eqlIgnoreCase(currency, "XAU") or std.ascii.eqlIgnoreCase(currency, "XAG");
}

pub fn displayRate(arena: std.mem.Allocator, currency: []const u8, stored: f64) f64 {
    if (!isMetal(currency) or stored <= 0) return stored;
    return usdBdtRate(arena) / stored;
}

pub fn setFiatRate(arena: std.mem.Allocator, currency: []const u8, units_per_usd: f64) !void {
    if (isMetal(currency)) return error.InvalidCurrency;
    if (units_per_usd <= 0) return error.InvalidRate;
    if (std.ascii.eqlIgnoreCase(currency, "USD")) return error.InvalidCurrency;
    const now = std.Io.Timestamp.now(zx.io(), .real).toSeconds();
    try upsert(try std.ascii.allocUpperString(arena, currency), units_per_usd, "manual", now);
}

fn cacheFresh(arena: std.mem.Allocator, gold_only: bool) bool {
    const Fresh = struct { fetched_at: i64, n: i64 };
    const row: ?Fresh = if (gold_only)
        (zx.db.row(arena, Fresh,
            \\SELECT MAX(fetched_at) AS fetched_at, COUNT(*) AS n
            \\FROM fx_rates WHERE currency = 'XAU' AND fetched_at > 0 AND as_of != 'seed'
        , .{}) catch return false)
    else
        (zx.db.row(arena, Fresh,
            \\SELECT MAX(fetched_at) AS fetched_at, COUNT(*) AS n
            \\FROM fx_rates
            \\WHERE currency NOT IN ('USD', 'XAU', 'XAG')
            \\  AND fetched_at > 0 AND as_of != 'seed'
        , .{}) catch return false);
    const r = row orelse return false;
    if (!gold_only and r.n < 3) return false;
    if (gold_only and r.n < 1) return false;
    const now = std.Io.Timestamp.now(zx.io(), .real).toSeconds();
    return now - r.fetched_at < cache_ttl_secs;
}

fn fetchFiat(arena: std.mem.Allocator) bool {
    var response = (zx.fetch(.blocking, arena, rates_url, .{
        .headers = &.{.{ .name = "User-Agent", .value = "nurulhudaapon.com" }},
        .timeout_ms = 12_000,
    }) catch null) orelse return false;
    defer response.deinit();
    if (!response.ok()) return false;
    const body = response.text() catch return false;

    const parsed = std.json.parseFromSlice([]RateRow, arena, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return false;

    const now = std.Io.Timestamp.now(zx.io(), .real).toSeconds();
    upsert("USD", 1, "live", now) catch {};

    var stored: usize = 0;
    for (parsed.value) |row| {
        if (!std.ascii.eqlIgnoreCase(row.base, "USD")) continue;
        if (row.quote.len != 3 or row.rate <= 0) continue;
        const quote = std.ascii.allocUpperString(arena, row.quote) catch continue;
        if (isMetal(quote)) continue;
        const as_of = if (row.date.len > 0) row.date else "live";
        upsert(quote, row.rate, as_of, now) catch continue;
        stored += 1;
    }
    return stored > 0;
}

fn fetchBajusGold(arena: std.mem.Allocator) bool {
    var response = (zx.fetch(.blocking, arena, bajus_url, .{
        .headers = &.{.{ .name = "User-Agent", .value = "nurulhudaapon.com" }},
        .timeout_ms = 15_000,
    }) catch null) orelse return false;
    defer response.deinit();
    if (!response.ok()) return false;
    const body = response.text() catch return false;

    const list_bdt = parseBajus22kBdtPerGram(body) orelse {
        zx.log.warn("fx: could not parse 22K gold price from bajus.org", .{});
        return false;
    };
    if (!cacheFresh(arena, false)) _ = fetchFiat(arena);
    const bdt_per_usd = usdBdtRate(arena);
    if (bdt_per_usd <= 0) return false;

    const effective_bdt = list_bdt * bajus_22k_haircut;
    const usd_per_g = effective_bdt / bdt_per_usd;
    if (usd_per_g <= 0) return false;

    const now = std.Io.Timestamp.now(zx.io(), .real).toSeconds();
    const as_of = std.fmt.allocPrint(arena, "bajus-{d:.0}", .{list_bdt}) catch "bajus";
    upsert("XAU", 1.0 / usd_per_g, as_of, now) catch return false;
    return true;
}

fn parseBajus22kBdtPerGram(html: []const u8) ?f64 {
    const table = sliceAfter(html, "gold-table") orelse return null;
    const row = sliceAfter(table, "22 KARAT Gold") orelse return null;
    const price_open = sliceAfter(row, "class=\"price\">") orelse
        sliceAfter(row, "class='price'>") orelse return null;
    const price_end = std.mem.indexOf(u8, price_open, "<") orelse return null;
    return parseBdtAmount(price_open[0..price_end]);
}

fn sliceAfter(hay: []const u8, needle: []const u8) ?[]const u8 {
    const i = std.mem.indexOf(u8, hay, needle) orelse return null;
    return hay[i + needle.len ..];
}

fn parseBdtAmount(raw: []const u8) ?f64 {
    var buf: [32]u8 = undefined;
    var n: usize = 0;
    for (raw) |c| {
        if (c >= '0' and c <= '9') {
            if (n >= buf.len) return null;
            buf[n] = c;
            n += 1;
        } else if (c == '.' and n > 0) {
            if (n >= buf.len) return null;
            buf[n] = c;
            n += 1;
        }
    }
    if (n == 0) return null;
    return std.fmt.parseFloat(f64, buf[0..n]) catch null;
}

fn upsert(currency: []const u8, rate: f64, as_of: []const u8, fetched_at: i64) !void {
    _ = try zx.db.run(
        \\INSERT INTO fx_rates (currency, rate, as_of, fetched_at)
        \\VALUES (?1, ?2, ?3, ?4)
        \\ON CONFLICT (currency) DO UPDATE SET
        \\  rate = excluded.rate,
        \\  as_of = excluded.as_of,
        \\  fetched_at = excluded.fetched_at
    , .{ currency, rate, as_of, fetched_at });
}

const RateRow = struct {
    date: []const u8 = "",
    base: []const u8 = "",
    quote: []const u8 = "",
    rate: f64 = 0,
};

test "parse bajus 22k price" {
    const html =
        \\<table class="table gold-table"><tbody>
        \\<tr><th><h6>22 KARAT Gold</h6></th>
        \\<td><p>CADMIUM</p></td>
        \\<td><span class="price">18,935 BDT/GRAM</span></td></tr>
        \\</tbody></table>
    ;
    try std.testing.expectEqual(@as(f64, 18935), parseBajus22kBdtPerGram(html).?);
}

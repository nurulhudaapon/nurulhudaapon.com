const std = @import("std");
const zx = @import("zx");

const rates_url = "https://api.frankfurter.dev/v2/rates?base=usd";
const bajus_url = "https://www.bajus.org/gold-price";
const cache_ttl_secs: i64 = 12 * 60 * 60;
const fallback_usd_bdt: f64 = 122;
const bajus_22k_haircut: f64 = 0.85;

// `rate` is units per USD; metals are stored as grams per USD.
pub const Rate = struct {
    currency: []const u8,
    rate: f64,
    as_of: []const u8,
    fetched_at: i64,
};

// Fetches only what is older than the cache TTL.
pub fn refresh(arena: std.mem.Allocator, io: std.Io) void {
    const client: Client = .{ .arena = arena, .io = io };
    if (!client.isFresh(.fiat)) _ = client.fetchFiat();
    if (!client.isFresh(.gold)) _ = client.fetchGold();
}

pub fn sync(arena: std.mem.Allocator, io: std.Io) !void {
    const client: Client = .{ .arena = arena, .io = io };
    const fiat_ok = client.fetchFiat();
    const gold_ok = client.fetchGold();
    if (!fiat_ok and !gold_ok) return error.FetchFailed;
}

pub fn rates(arena: std.mem.Allocator) ![]const Rate {
    return try zx.db.rows(arena, Rate,
        \\SELECT currency, rate, as_of, fetched_at FROM fx_rates
        \\ORDER BY
        \\  CASE currency
        \\    WHEN 'USD' THEN 0 WHEN 'BDT' THEN 1 WHEN 'XAU' THEN 2 WHEN 'XAG' THEN 3
        \\    ELSE 4 END,
        \\  currency
    , .{});
}

pub fn currencies(arena: std.mem.Allocator) ![]const []const u8 {
    const all = try rates(arena);
    const out = try arena.alloc([]const u8, all.len);
    for (all, 0..) |r, i| out[i] = r.currency;
    return out;
}

pub fn usdBdt(arena: std.mem.Allocator) f64 {
    const row = zx.db.row(arena, struct { rate: f64 },
        \\SELECT rate FROM fx_rates WHERE currency = 'BDT' LIMIT 1
    , .{}) catch return fallback_usd_bdt;
    const r = row orelse return fallback_usd_bdt;
    return if (r.rate > 0) r.rate else fallback_usd_bdt;
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

// Metals display as BDT per gram; everything else as stored.
pub fn displayRate(arena: std.mem.Allocator, currency: []const u8, stored: f64) f64 {
    if (!isMetal(currency) or stored <= 0) return stored;
    return usdBdt(arena) / stored;
}

pub fn setRate(arena: std.mem.Allocator, io: std.Io, currency: []const u8, units_per_usd: f64) !void {
    if (isMetal(currency)) return error.InvalidCurrency;
    if (units_per_usd <= 0) return error.InvalidRate;
    if (std.ascii.eqlIgnoreCase(currency, "USD")) return error.InvalidCurrency;
    const now = std.Io.Timestamp.now(io, .real).toSeconds();
    try upsert(try std.ascii.allocUpperString(arena, currency), units_per_usd, "manual", now);
}

const Client = struct {
    arena: std.mem.Allocator,
    io: std.Io,

    const Kind = enum { fiat, gold };

    fn isFresh(c: Client, kind: Kind) bool {
        const Fresh = struct { fetched_at: i64, n: i64 };
        const row: ?Fresh = switch (kind) {
            .gold => zx.db.row(c.arena, Fresh,
                \\SELECT MAX(fetched_at) AS fetched_at, COUNT(*) AS n
                \\FROM fx_rates WHERE currency = 'XAU' AND fetched_at > 0 AND as_of != 'seed'
            , .{}) catch return false,
            .fiat => zx.db.row(c.arena, Fresh,
                \\SELECT MAX(fetched_at) AS fetched_at, COUNT(*) AS n
                \\FROM fx_rates
                \\WHERE currency NOT IN ('USD', 'XAU', 'XAG')
                \\  AND fetched_at > 0 AND as_of != 'seed'
            , .{}) catch return false,
        };
        const r = row orelse return false;
        const min_rows: i64 = if (kind == .fiat) 3 else 1;
        if (r.n < min_rows) return false;
        return c.now() - r.fetched_at < cache_ttl_secs;
    }

    fn fetchFiat(c: Client) bool {
        const body = c.get(rates_url, 12_000) orelse return false;
        const parsed = std.json.parseFromSlice([]RateRow, c.arena, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return false;

        const fetched_at = c.now();
        upsert("USD", 1, "live", fetched_at) catch {};

        var stored: usize = 0;
        for (parsed.value) |row| {
            if (!std.ascii.eqlIgnoreCase(row.base, "USD")) continue;
            if (row.quote.len != 3 or row.rate <= 0) continue;
            const quote = std.ascii.allocUpperString(c.arena, row.quote) catch continue;
            if (isMetal(quote)) continue;
            const as_of = if (row.date.len > 0) row.date else "live";
            upsert(quote, row.rate, as_of, fetched_at) catch continue;
            stored += 1;
        }
        return stored > 0;
    }

    // Gold is priced in BDT, so it needs a current USD/BDT rate first.
    fn fetchGold(c: Client) bool {
        const body = c.get(bajus_url, 15_000) orelse return false;
        const list_bdt = parseBajus22k(body) orelse {
            zx.log.warn("fx: could not parse 22K gold price from bajus.org", .{});
            return false;
        };
        if (!c.isFresh(.fiat)) _ = c.fetchFiat();
        const bdt_per_usd = usdBdt(c.arena);
        if (bdt_per_usd <= 0) return false;

        const usd_per_g = list_bdt * bajus_22k_haircut / bdt_per_usd;
        if (usd_per_g <= 0) return false;

        const as_of = c.arena.print("bajus-{d:.0}", .{list_bdt}) catch "bajus";
        upsert("XAU", 1.0 / usd_per_g, as_of, c.now()) catch return false;
        return true;
    }

    fn get(c: Client, url: []const u8, timeout_ms: i64) ?[]const u8 {
        var http: zx.http.Client = .{ .io = c.io, .allocator = c.arena };
        defer http.deinit();
        const response = http.fetch(.{
            .url = url,
            .headers = &.{.{ .name = "User-Agent", .value = "nurulhudaapon.com" }},
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake } },
        }) catch return null;
        defer response.deinit(c.arena);
        if (response.status.class() != .success) return null;
        return c.arena.dupe(u8, response.body) catch null;
    }

    fn now(c: Client) i64 {
        return std.Io.Timestamp.now(c.io, .real).toSeconds();
    }
};

// BDT per gram from the "22 KARAT Gold" row of the BAJUS price table.
fn parseBajus22k(html: []const u8) ?f64 {
    const table = sliceAfter(html, "gold-table") orelse return null;
    const row = sliceAfter(table, "22 KARAT Gold") orelse return null;
    const price_open = sliceAfter(row, "class=\"price\">") orelse
        sliceAfter(row, "class='price'>") orelse return null;
    const price_end = std.mem.indexOf(u8, price_open, "<") orelse return null;
    return parseAmount(price_open[0..price_end]);
}

fn sliceAfter(hay: []const u8, needle: []const u8) ?[]const u8 {
    const i = std.mem.indexOf(u8, hay, needle) orelse return null;
    return hay[i + needle.len ..];
}

// Keeps digits and decimal points, dropping grouping commas and units.
fn parseAmount(raw: []const u8) ?f64 {
    var buf: [32]u8 = undefined;
    var n: usize = 0;
    for (raw) |c| {
        if ((c >= '0' and c <= '9') or (c == '.' and n > 0)) {
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
    try std.testing.expectEqual(@as(f64, 18935), parseBajus22k(html).?);
}

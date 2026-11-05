const std = @import("std");
const mcp = @import("mcp");
const posts = @import("../blog.zig").posts;
const slots = @import("../schedule.zig").slots;
const settings = @import("../schedule.zig").settings;
const caldav = @import("../schedule.zig").caldav;
const calendars = @import("../schedule.zig").calendars;
const booking = @import("../schedule.zig").booking;
const github = @import("../github.zig");
const finance = @import("../finance.zig");
const fx = @import("../finance/fx.zig");
const ask = @import("../ask.zig");

pub fn handle(arena: std.mem.Allocator, io: std.Io, body: []const u8) ![]u8 {
    var request: Request = .{ .arena = arena, .io = io };
    var server = try create(arena);
    defer server.deinit();
    return server.handleMessage(arena, &request, body);
}

const Request = struct {
    arena: std.mem.Allocator,
    io: std.Io,
};

const Server = mcp.Server(*Request);
const Args = ?std.json.Value;
const Result = anyerror!mcp.ToolResult;

const readonly = mcp.types.ToolAnnotations{ .readOnlyHint = true, .idempotentHint = true };

fn create(allocator: std.mem.Allocator) !Server {
    var server = Server.init(allocator, .{
        .name = "nurulhudaapon.com",
        .version = "3.0.0",
        .title = "nurulhudaapon.com MCP",
        .instructions = "Read-only tools: blog, schedule/bookings, questions, GitHub pins, and finance (USD/BDT).",
    });
    try server.addTool(.{
        .name = "site_info",
        .description = "Public site metadata.",
        .annotations = readonly,
    }, siteInfo);
    try server.addTool(.{
        .name = "list_blog_posts",
        .description = "List published blog posts (no full body).",
        .annotations = readonly,
    }, listPosts);
    try server.addTool(.{
        .name = "get_blog_post",
        .description = "Fetch one blog post by slug (includes markdown body).",
        .input_schema_json =
        \\{"type":"object","properties":{"slug":{"type":"string","description":"Post slug"}},"required":["slug"],"additionalProperties":false}
        ,
        .annotations = readonly,
    }, getPost);
    try server.addTool(.{
        .name = "list_schedule_availability",
        .description = "Open booking slots over the schedule horizon (Asia/Dhaka).",
        .annotations = readonly,
    }, listAvailability);
    try server.addTool(.{
        .name = "list_github_repos",
        .description = "Pinned GitHub repositories with stars and forks.",
        .annotations = readonly,
    }, listRepos);
    try server.addTool(.{
        .name = "finance_summary",
        .description = "Portfolio totals: net worth, cash, invested, FX (USD/BDT).",
        .annotations = readonly,
    }, financeSummary);
    try server.addTool(.{
        .name = "list_finance_accounts",
        .description = "Broker/manual accounts with USD values and portfolio weight.",
        .annotations = readonly,
    }, listAccounts);
    try server.addTool(.{
        .name = "list_finance_holdings",
        .description = "Holdings sorted by market value (USD base). Optional limit (default 25).",
        .input_schema_json =
        \\{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":200,"description":"Max holdings to return"}},"additionalProperties":false}
        ,
        .annotations = readonly,
    }, listHoldings);
    try server.addTool(.{
        .name = "list_finance_allocations",
        .description = "Target vs actual asset-class allocation percentages.",
        .annotations = readonly,
    }, listAllocations);
    try server.addTool(.{
        .name = "list_fx_rates",
        .description = "Stored FX rates (units per USD) including BDT and metals.",
        .annotations = readonly,
    }, listRates);
    try server.addTool(.{
        .name = "list_zakat",
        .description = "Recorded zakat payments by year.",
        .annotations = readonly,
    }, listZakat);
    try server.addTool(.{
        .name = "list_bookings",
        .description = "Schedule bookings. filter: upcoming|past|cancelled (default upcoming). Optional limit (default 50).",
        .input_schema_json =
        \\{"type":"object","properties":{"filter":{"type":"string","enum":["upcoming","past","cancelled"]},"limit":{"type":"integer","minimum":1,"maximum":200}},"additionalProperties":false}
        ,
        .annotations = readonly,
    }, listBookings);
    try server.addTool(.{
        .name = "get_booking",
        .description = "Fetch one booking by id.",
        .input_schema_json =
        \\{"type":"object","properties":{"id":{"type":"string","description":"Booking id"}},"required":["id"],"additionalProperties":false}
        ,
        .annotations = readonly,
    }, getBooking);
    try server.addTool(.{
        .name = "list_questions",
        .description = "Ask-page questions. filter: unanswered|answered|all (default unanswered).",
        .input_schema_json =
        \\{"type":"object","properties":{"filter":{"type":"string","enum":["unanswered","answered","all"]}},"additionalProperties":false}
        ,
        .annotations = readonly,
    }, listQuestions);
    return server;
}

fn siteInfo(r: *Request, _: Args) Result {
    return mcp.ToolResult.fromValue(r.arena, .{
        .name = "nurulhudaapon.com",
        .version = "3.0.0",
        .url = "https://nurulhudaapon.com",
        .mcp = "/mcp",
        .blog = "/blog",
        .schedule = "/schedule",
    });
}

const PostSummary = struct {
    slug: []const u8,
    title: []const u8,
    brief: []const u8,
    url: []const u8,
    publishedAt: []const u8,
    readTimeInMinutes: u32,
};

fn listPosts(r: *Request, _: Args) Result {
    const all = try posts.list(r.arena, r.io);
    const out = try r.arena.alloc(PostSummary, all.len);
    for (all, out) |p, *s| s.* = .{
        .slug = p.slug,
        .title = p.title,
        .brief = p.brief,
        .url = p.url,
        .publishedAt = p.date,
        .readTimeInMinutes = p.read_minutes,
    };
    return mcp.ToolResult.fromValue(r.arena, .{ .posts = out });
}

fn getPost(r: *Request, args: Args) Result {
    const slug = argString(args, "slug") orelse return mcp.ToolResult.err(r.arena, "Missing required argument: slug");
    const post = posts.get(r.arena, r.io, slug, .markdown) catch |err| switch (err) {
        error.PostNotFound => return mcp.ToolResult.err(r.arena, "Post not found"),
        else => return err,
    };
    return mcp.ToolResult.fromValue(r.arena, .{
        .slug = post.slug,
        .title = post.title,
        .brief = post.brief,
        .url = post.url,
        .publishedAt = post.date,
        .readTimeInMinutes = post.read_minutes,
        .content = post.content,
        .coverImage = post.cover,
    });
}

fn listAvailability(r: *Request, _: Args) Result {
    const rules = settings.load(r.arena);
    const now = std.Io.Timestamp.now(r.io, .real).toSeconds();
    const range = slots.horizon(rules, now);
    const busy = if (try caldav.credentials(r.arena)) |creds|
        (try calendars.busy(r.arena, r.io, creds, range, false)).intervals
    else
        &[_]slots.Interval{};
    const days = try slots.availableDays(r.arena, rules, now, busy);

    const Slot = struct { start: i64, end: i64, label: []const u8 };
    const Day = struct { date: []const u8, weekday: []const u8, slots: []const Slot };
    const out = try r.arena.alloc(Day, days.len);
    for (days, out) |day, *d| {
        const day_slots = try r.arena.alloc(Slot, day.slots.len);
        for (day.slots, day_slots) |slot, *s| s.* = .{
            .start = slot.start,
            .end = slot.end,
            .label = try slots.formatTime12(r.arena, slot.start, slots.config.utc_offset_s),
        };
        d.* = .{ .date = day.date, .weekday = day.weekday, .slots = day_slots };
    }
    return mcp.ToolResult.fromValue(r.arena, .{
        .timezone = slots.config.timezone,
        .timezone_label = slots.config.timezone_label,
        .slot_minutes = rules.slot_minutes,
        .days = out,
    });
}

fn listRepos(r: *Request, _: Args) Result {
    const repos = github.Client.init(r.arena, r.io).pinned() catch |err| {
        return mcp.ToolResult.err(r.arena, try r.arena.print("GitHub unavailable: {s}", .{@errorName(err)}));
    };
    return mcp.ToolResult.fromValue(r.arena, .{ .repos = repos });
}

fn financeSummary(r: *Request, _: Args) Result {
    return mcp.ToolResult.fromValue(r.arena, try finance.portfolio.summary(r.arena));
}

const AccountOut = struct {
    id: i64,
    name: []const u8,
    broker: []const u8,
    institution: []const u8,
    group: []const u8,
    account_type: []const u8,
    asset_class: []const u8,
    currency: []const u8,
    cash: f64,
    net_liquidation: f64,
    value_usd: f64,
    cash_usd: f64,
    weight_pct: f64,
    stale: bool,
    liability: bool,
    synced_at: ?[]const u8,
    notes: ?[]const u8,
};

fn listAccounts(r: *Request, _: Args) Result {
    const accounts = try finance.accounts.list(r.arena);
    const out = try r.arena.alloc(AccountOut, accounts.len);
    for (accounts, out) |a, *o| o.* = .{
        .id = a.id,
        .name = a.name,
        .broker = a.broker,
        .institution = a.institution,
        .group = a.group_name,
        .account_type = a.account_type,
        .asset_class = a.asset_class,
        .currency = a.currency,
        .cash = a.cash,
        .net_liquidation = a.net_liquidation,
        .value_usd = a.value_usd,
        .cash_usd = a.cash_usd,
        .weight_pct = a.weight_pct,
        .stale = a.stale != 0,
        .liability = a.liability != 0,
        .synced_at = a.synced_at,
        .notes = a.notes,
    };
    return mcp.ToolResult.fromValue(r.arena, .{ .accounts = out });
}

fn listHoldings(r: *Request, args: Args) Result {
    const limit: usize = @intCast(std.math.clamp(argInt(args, "limit") orelse 25, 1, 200));
    const holdings = try finance.holdings.list(r.arena, limit);
    return mcp.ToolResult.fromValue(r.arena, .{ .holdings = holdings, .limit = limit });
}

fn listAllocations(r: *Request, _: Args) Result {
    return mcp.ToolResult.fromValue(r.arena, .{ .allocations = try finance.allocations.actuals(r.arena) });
}

fn listRates(r: *Request, _: Args) Result {
    return mcp.ToolResult.fromValue(r.arena, .{ .rates = try fx.rates(r.arena), .base = "USD" });
}

fn listZakat(r: *Request, _: Args) Result {
    return mcp.ToolResult.fromValue(r.arena, .{
        .entries = try finance.zakat.list(r.arena),
        .gold_nisab_grams = finance.zakat.gold_nisab_grams,
    });
}

fn listBookings(r: *Request, args: Args) Result {
    const filter_name = argString(args, "filter") orelse "upcoming";
    const filter = std.meta.stringToEnum(booking.Filter, filter_name) orelse {
        return mcp.ToolResult.err(r.arena, "filter must be upcoming, past, or cancelled");
    };
    const limit = std.math.clamp(argInt(args, "limit") orelse 50, 1, 200);
    const now = std.Io.Timestamp.now(r.io, .real).toSeconds();
    const rows = try booking.list(r.arena, filter, limit, now);
    return mcp.ToolResult.fromValue(r.arena, .{ .filter = filter_name, .limit = limit, .bookings = rows });
}

fn getBooking(r: *Request, args: Args) Result {
    const id = argString(args, "id") orelse return mcp.ToolResult.err(r.arena, "Missing required argument: id");
    const row = try booking.get(r.arena, r.io, id) orelse return mcp.ToolResult.err(r.arena, "Booking not found");
    return mcp.ToolResult.fromValue(r.arena, row);
}

fn listQuestions(r: *Request, args: Args) Result {
    const filter_name = argString(args, "filter") orelse "unanswered";
    const filter = std.meta.stringToEnum(ask.Filter, filter_name) orelse {
        return mcp.ToolResult.err(r.arena, "filter must be unanswered, answered, or all");
    };
    return mcp.ToolResult.fromValue(r.arena, .{
        .filter = filter_name,
        .counts = ask.counts(r.arena),
        .questions = try ask.list(r.arena, filter),
    });
}

fn arg(args: Args, key: []const u8) ?std.json.Value {
    const obj = args orelse return null;
    if (obj != .object) return null;
    return obj.object.get(key);
}

fn argString(args: Args, key: []const u8) ?[]const u8 {
    const v = arg(args, key) orelse return null;
    return if (v == .string) v.string else null;
}

fn argInt(args: Args, key: []const u8) ?i64 {
    return switch (arg(args, key) orelse return null) {
        .integer => |n| n,
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

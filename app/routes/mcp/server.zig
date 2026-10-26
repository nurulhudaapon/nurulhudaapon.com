const std = @import("std");
const mcp = @import("mcp");
const posts = @import("../../pages/blog/posts.zig");
const slots = @import("../../pages/schedule/slots.zig");
const schedule_settings = @import("../../pages/schedule/settings.zig");
const caldav = @import("../../pages/schedule/caldav.zig");
const booking = @import("../../pages/schedule/booking.zig");
const github = @import("../../pages/dev/github.zig");
const finance = @import("../../pages/finance/db.zig");
const fx = @import("../../pages/finance/fx.zig");
const ask_db = @import("../../pages/ask/db.zig");

const readonly = mcp.types.ToolAnnotations{ .readOnlyHint = true, .idempotentHint = true };

pub fn create(allocator: std.mem.Allocator) !mcp.Server {
    var server = mcp.Server.init(allocator, .{
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
    }, listBlogPosts);
    try server.addTool(.{
        .name = "get_blog_post",
        .description = "Fetch one blog post by slug (includes markdown body).",
        .input_schema_json =
            \\{"type":"object","properties":{"slug":{"type":"string","description":"Post slug"}},"required":["slug"],"additionalProperties":false}
        ,
        .annotations = readonly,
    }, getBlogPost);
    try server.addTool(.{
        .name = "list_schedule_availability",
        .description = "Open booking slots over the schedule horizon (Asia/Dhaka).",
        .annotations = readonly,
    }, listScheduleAvailability);
    try server.addTool(.{
        .name = "list_github_repos",
        .description = "Pinned GitHub repositories with stars and forks.",
        .annotations = readonly,
    }, listGithubRepos);
    try server.addTool(.{
        .name = "finance_summary",
        .description = "Portfolio totals: net worth, cash, invested, FX (USD/BDT).",
        .annotations = readonly,
    }, financeSummary);
    try server.addTool(.{
        .name = "list_finance_accounts",
        .description = "Broker/manual accounts with USD values and portfolio weight.",
        .annotations = readonly,
    }, listFinanceAccounts);
    try server.addTool(.{
        .name = "list_finance_holdings",
        .description = "Holdings sorted by market value (USD base). Optional limit (default 25).",
        .input_schema_json =
            \\{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":200,"description":"Max holdings to return"}},"additionalProperties":false}
        ,
        .annotations = readonly,
    }, listFinanceHoldings);
    try server.addTool(.{
        .name = "list_finance_allocations",
        .description = "Target vs actual asset-class allocation percentages.",
        .annotations = readonly,
    }, listFinanceAllocations);
    try server.addTool(.{
        .name = "list_fx_rates",
        .description = "Stored FX rates (units per USD) including BDT and metals.",
        .annotations = readonly,
    }, listFxRates);
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

pub fn handle(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    var server = try create(allocator);
    defer server.deinit();
    return server.handleMessage(allocator, body);
}

fn siteInfo(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    return mcp.ToolResult.fromValue(allocator, .{
        .name = "nurulhudaapon.com",
        .version = "3.0.0",
        .url = "https://nurulhudaapon.com",
        .mcp = "/mcp",
        .blog = "/blog",
        .schedule = "/schedule",
    });
}

fn listBlogPosts(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const all = try posts.getPosts(allocator);
    const Summary = struct {
        slug: []const u8,
        title: []const u8,
        brief: []const u8,
        url: []const u8,
        publishedAt: []const u8,
        readTimeInMinutes: u32,
    };
    const out = try allocator.alloc(Summary, all.len);
    for (all, out) |p, *s| {
        s.* = .{
            .slug = p.slug,
            .title = p.title,
            .brief = p.brief,
            .url = p.url,
            .publishedAt = p.publishedAt,
            .readTimeInMinutes = p.readTimeInMinutes,
        };
    }
    return mcp.ToolResult.fromValue(allocator, .{ .posts = out });
}

fn getBlogPost(allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!mcp.ToolResult {
    const slug = argString(args, "slug") orelse {
        return mcp.ToolResult.err(allocator, "Missing required argument: slug");
    };
    const post = posts.getPostBySlug(allocator, slug) catch |err| switch (err) {
        error.PostNotFound => return mcp.ToolResult.err(allocator, "Post not found"),
        else => return err,
    };
    return mcp.ToolResult.fromValue(allocator, .{
        .slug = post.slug,
        .title = post.title,
        .brief = post.brief,
        .url = post.url,
        .publishedAt = post.publishedAt,
        .readTimeInMinutes = post.readTimeInMinutes,
        .content = post.content,
        .coverImage = post.coverImage,
    });
}

fn listScheduleAvailability(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const rules = schedule_settings.load(allocator);
    const now = booking.nowUnix();
    const range = slots.horizon(rules, now);
    const busy = if (try caldav.loadCredentials(allocator)) |creds|
        try caldav.busy(allocator, creds, range, true)
    else
        &[_]slots.Interval{};
    const days = try slots.availableDays(allocator, rules, now, busy);

    const SlotOut = struct { start: i64, end: i64, label: []const u8 };
    const DayOut = struct {
        date: []const u8,
        weekday: []const u8,
        slots: []const SlotOut,
    };
    const out_days = try allocator.alloc(DayOut, days.len);
    for (days, out_days) |day, *d| {
        const out_slots = try allocator.alloc(SlotOut, day.slots.len);
        for (day.slots, out_slots) |slot, *s| {
            s.* = .{
                .start = slot.start,
                .end = slot.end,
                .label = try slots.formatTime12(allocator, slot.start, slots.config.utc_offset_s),
            };
        }
        d.* = .{ .date = day.date, .weekday = day.weekday, .slots = out_slots };
    }
    return mcp.ToolResult.fromValue(allocator, .{
        .timezone = slots.config.timezone,
        .timezone_label = slots.config.timezone_label,
        .slot_minutes = rules.slot_minutes,
        .days = out_days,
    });
}

fn listGithubRepos(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const repos = github.fetchPinned(allocator) catch |err| {
        return mcp.ToolResult.err(allocator, try std.fmt.allocPrint(allocator, "GitHub unavailable: {s}", .{@errorName(err)}));
    };
    return mcp.ToolResult.fromValue(allocator, .{ .repos = repos });
}

fn financeSummary(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const summary = try finance.portfolioSummary(allocator);
    return mcp.ToolResult.fromValue(allocator, summary);
}

fn listFinanceAccounts(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const rows = try finance.listAccountRows(allocator);
    const Out = struct {
        id: i64,
        name: []const u8,
        broker: []const u8,
        institution: []const u8,
        account_type: []const u8,
        asset_class: []const u8,
        currency: []const u8,
        cash: f64,
        net_liquidation: f64,
        value_usd: f64,
        cash_usd: f64,
        weight_pct: f64,
        stale: bool,
        synced_at: ?[]const u8,
        notes: ?[]const u8,
    };
    const out = try allocator.alloc(Out, rows.len);
    for (rows, out) |row, *o| {
        o.* = .{
            .id = row.account.id,
            .name = row.account.name,
            .broker = row.account.broker,
            .institution = row.account.institution,
            .account_type = row.account.account_type,
            .asset_class = row.account.asset_class,
            .currency = row.account.currency,
            .cash = row.account.cash,
            .net_liquidation = row.account.net_liquidation,
            .value_usd = row.value_usd,
            .cash_usd = row.cash_usd,
            .weight_pct = row.weight_pct,
            .stale = row.account.stale != 0,
            .synced_at = row.account.synced_at,
            .notes = row.account.notes,
        };
    }
    return mcp.ToolResult.fromValue(allocator, .{ .accounts = out });
}

fn listFinanceHoldings(allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!mcp.ToolResult {
    const limit: usize = blk: {
        const n = argInt(args, "limit") orelse break :blk 25;
        break :blk @intCast(@min(@max(n, 1), 200));
    };
    const holdings = try finance.listHoldingsLimited(allocator, limit);
    return mcp.ToolResult.fromValue(allocator, .{ .holdings = holdings, .limit = limit });
}

fn listFinanceAllocations(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const allocations = try finance.listAllocationActuals(allocator);
    return mcp.ToolResult.fromValue(allocator, .{ .allocations = allocations });
}

fn listFxRates(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const rates = try fx.listRates(allocator);
    return mcp.ToolResult.fromValue(allocator, .{ .rates = rates, .base = "USD" });
}

fn listZakat(allocator: std.mem.Allocator, _: ?std.json.Value) anyerror!mcp.ToolResult {
    const entries = try finance.listZakat(allocator);
    return mcp.ToolResult.fromValue(allocator, .{
        .entries = entries,
        .gold_nisab_grams = finance.gold_nisab_grams,
    });
}

fn listBookings(allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!mcp.ToolResult {
    const filter_s = argString(args, "filter") orelse "upcoming";
    const filter = std.meta.stringToEnum(booking.Filter, filter_s) orelse {
        return mcp.ToolResult.err(allocator, "filter must be upcoming, past, or cancelled");
    };
    const limit: i64 = blk: {
        const n = argInt(args, "limit") orelse break :blk 50;
        break :blk @min(@max(n, 1), 200);
    };
    const rows = try booking.list(allocator, filter, limit);
    return mcp.ToolResult.fromValue(allocator, .{ .filter = filter_s, .limit = limit, .bookings = rows });
}

fn getBooking(allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!mcp.ToolResult {
    const id = argString(args, "id") orelse {
        return mcp.ToolResult.err(allocator, "Missing required argument: id");
    };
    const row = (try booking.get(allocator, id)) orelse {
        return mcp.ToolResult.err(allocator, "Booking not found");
    };
    return mcp.ToolResult.fromValue(allocator, row);
}

fn listQuestions(allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!mcp.ToolResult {
    const filter_s = argString(args, "filter") orelse "unanswered";
    const filter = std.meta.stringToEnum(ask_db.Filter, filter_s) orelse {
        return mcp.ToolResult.err(allocator, "filter must be unanswered, answered, or all");
    };
    const rows = try ask_db.listFiltered(allocator, filter);
    return mcp.ToolResult.fromValue(allocator, .{
        .filter = filter_s,
        .counts = ask_db.counts(allocator),
        .questions = rows,
    });
}

fn argString(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    const obj = args orelse return null;
    if (obj != .object) return null;
    const v = obj.object.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn argInt(args: ?std.json.Value, key: []const u8) ?i64 {
    const obj = args orelse return null;
    if (obj != .object) return null;
    const v = obj.object.get(key) orelse return null;
    return switch (v) {
        .integer => |n| n,
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

const std = @import("std");
const zx = @import("zx");

pub const Repo = struct {
    name: []const u8,
    full_name: []const u8,
    html_url: []const u8,
    description: ?[]const u8 = null,
    homepage: ?[]const u8 = null,
    language: ?[]const u8 = null,
    stargazers_count: u32,
    forks_count: u32,
};

pub const Stats = struct {
    repo: []const u8,
    stars: u32,
    forks: u32,
};

pub const endpoint = "/api/data/github.zon";

/// Set at startup from `GITHUB_TOKEN`; unauthenticated requests are limited to 60/hour per IP.
var auth_header: ?[]const u8 = null;

pub fn setToken(token: []const u8) !void {
    if (auth_header) |old| zx.allocator.free(old);
    auth_header = try zx.allocator.print("Bearer {s}", .{token});
}

pub fn authorization() ?[]const u8 {
    return auth_header;
}

const owners = [_][]const u8{ "ziex-dev", "nurulhudaapon" };

const pinned = [_][]const u8{
    "ziex-dev/ziex",
    "nurulhudaapon/zzon",
    "nurulhudaapon/temporalz",
    "nurulhudaapon/prisma-supabase",
    "ziex-dev/zigc",
    "nurulhudaapon/lunasvg",
    "nurulhudaapon/bun-plugin-zon",
    "nurulhudaapon/enum-map-generator",
    "nurulhudaapon/nx-sst-next",
    "nurulhudaapon/supabase-mock-fetch",
    "nurulhudaapon/asdf-sst",
};

pub fn fetchPinned(arena: std.mem.Allocator) ![]const Repo {
    var by_name: std.StringHashMapUnmanaged(Repo) = .empty;
    for (owners) |owner| {
        const url = try arena.print("https://api.github.com/users/{s}/repos?per_page=100", .{owner});
        const headers = [_]zx.Fetch.RequestInit.Header{
            .{ .name = "Accept", .value = "application/vnd.github+json" },
            .{ .name = "User-Agent", .value = "nuhu.dev" },
            .{ .name = "Authorization", .value = auth_header orelse "" },
        };
        var response = (try zx.fetch(.blocking, arena, url, .{
            .headers = if (auth_header != null) &headers else headers[0..2],
            .timeout_ms = 5_000,
        })) orelse return error.EmptyResponse;
        defer response.deinit();
        if (!response.ok()) {
            zx.log.warn("github: {s} returned {d}", .{ url, response.status });
            return error.GitHubUnavailable;
        }

        const parsed = try response.json([]const Repo);
        for (parsed.value) |repo| try by_name.put(arena, repo.full_name, repo);
    }

    var repos: std.ArrayList(Repo) = .empty;
    for (pinned) |name| {
        if (by_name.get(name)) |repo| try repos.append(arena, repo);
    }
    return repos.toOwnedSlice(arena);
}

pub fn fetchStats(arena: std.mem.Allocator) ![]const Stats {
    const repos = try fetchPinned(arena);
    const stats = try arena.alloc(Stats, repos.len);
    for (repos, stats) |r, *s| s.* = .{ .repo = r.full_name, .stars = r.stargazers_count, .forks = r.forks_count };
    return stats;
}

pub fn compact(allocator: std.mem.Allocator, n: u32) []const u8 {
    const out = if (n < 1000)
        allocator.print("{d}", .{n})
    else if (n < 10_000 and (n + 50) / 100 % 10 != 0)
        allocator.print("{d}.{d}k", .{ (n + 50) / 1000, (n + 50) / 100 % 10 })
    else
        allocator.print("{d}k", .{(n + 500) / 1000});
    return out catch "";
}

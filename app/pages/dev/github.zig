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
        const url = try std.fmt.allocPrint(arena, "https://api.github.com/users/{s}/repos?per_page=100", .{owner});
        var response = (try zx.fetch(.blocking, arena, url, .{
            .headers = &.{
                .{ .name = "Accept", .value = "application/vnd.github+json" },
                .{ .name = "User-Agent", .value = "nuhu.dev" },
            },
            .timeout_ms = 5_000,
        })) orelse return error.EmptyResponse;
        defer response.deinit();
        if (!response.ok()) return error.GitHubUnavailable;

        const parsed = try response.json([]const Repo);
        for (parsed.value) |repo| try by_name.put(arena, repo.full_name, repo);
    }

    var repos: std.ArrayList(Repo) = .empty;
    for (pinned) |name| {
        if (by_name.get(name)) |repo| try repos.append(arena, repo);
    }
    return repos.toOwnedSlice(arena);
}

pub fn compact(allocator: std.mem.Allocator, n: u32) []const u8 {
    const out = if (n < 1000)
        std.fmt.allocPrint(allocator, "{d}", .{n})
    else if (n < 10_000 and (n + 50) / 100 % 10 != 0)
        std.fmt.allocPrint(allocator, "{d}.{d}k", .{ (n + 50) / 1000, (n + 50) / 100 % 10 })
    else
        std.fmt.allocPrint(allocator, "{d}k", .{(n + 500) / 1000});
    return out catch "";
}

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

pub const endpoint = "/api/data/github.json";

// Unauthenticated requests are limited to 60/hour per IP.
var auth_header: ?[]const u8 = null;

pub fn setToken(token: []const u8) !void {
    if (auth_header) |old| zx.allocator.free(old);
    auth_header = try zx.allocator.print("Bearer {s}", .{token});
}

pub fn authorization() ?[]const u8 {
    return auth_header;
}

const owners = [_][]const u8{ "ziex-dev", "nurulhudaapon" };

const pinned_names = [_][]const u8{
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

pub const Client = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    authorization: ?[]const u8,

    pub fn init(arena: std.mem.Allocator, io: std.Io) Client {
        return .{ .arena = arena, .io = io, .authorization = auth_header };
    }

    pub fn pinned(c: Client) ![]const Repo {
        var by_name: std.StringHashMapUnmanaged(Repo) = .empty;
        for (owners) |owner| {
            const url = try c.arena.print("https://api.github.com/users/{s}/repos?per_page=100", .{owner});
            for (try c.get([]const Repo, url)) |repo| try by_name.put(c.arena, repo.full_name, repo);
        }

        var repos: std.ArrayList(Repo) = .empty;
        for (pinned_names) |name| {
            if (by_name.get(name)) |repo| try repos.append(c.arena, repo);
        }
        return repos.toOwnedSlice(c.arena);
    }

    pub fn stats(c: Client) ![]const Stats {
        const repos = try c.pinned();
        const out = try c.arena.alloc(Stats, repos.len);
        for (repos, out) |r, *s| s.* = .{ .repo = r.full_name, .stars = r.stargazers_count, .forks = r.forks_count };
        return out;
    }

    fn get(c: Client, comptime T: type, url: []const u8) !T {
        const headers = [_]zx.http.Header{
            .{ .name = "Accept", .value = "application/vnd.github+json" },
            .{ .name = "User-Agent", .value = "nuhu.dev" },
            .{ .name = "Authorization", .value = c.authorization orelse "" },
        };
        var client: zx.http.Client = .{ .io = c.io, .allocator = c.arena };
        defer client.deinit();
        const response = try client.fetch(.{
            .url = url,
            .headers = if (c.authorization != null) &headers else headers[0..2],
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(5_000), .clock = .awake } },
        });
        defer response.deinit(c.arena);
        if (response.status.class() != .success) {
            zx.log.warn("github: {s} returned {d}", .{ url, @backingInt(response.status) });
            return error.GitHubUnavailable;
        }
        return (try response.json(T, c.arena)).value;
    }
};

pub fn compact(allocator: std.mem.Allocator, n: u32) []const u8 {
    const out = if (n < 1000)
        allocator.print("{d}", .{n})
    else if (n < 10_000 and (n + 50) / 100 % 10 != 0)
        allocator.print("{d}.{d}k", .{ (n + 50) / 1000, (n + 50) / 100 % 10 })
    else
        allocator.print("{d}k", .{(n + 500) / 1000});
    return out catch "";
}

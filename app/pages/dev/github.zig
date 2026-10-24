const std = @import("std");

const GITHUB_API_URLS = [_][]const u8{
    "https://api.github.com/users/ziex-dev/repos?per_page=100",
    "https://api.github.com/users/nurulhudaapon/repos?per_page=100",
};

const PINNED_REPOS = [_][]const u8{
    "ziex",
    "zzon",
    "prisma-supabase",
    "nx-sst-next",
    "enum-map-generator",
    "temporalz",
    "bencher",
    "supabase-mock-fetch",
};

pub const Project = struct {
    name: []const u8,
    description: []const u8,
    language: []const u8,
    stars: u32,
    forks: u32,
    url: []const u8,
};

pub fn getPinnedRepos(allocator: std.mem.Allocator) ![]Project {
    var client = std.http.Client{ .allocator = allocator, .io = std.Io.Threaded.global_single_threaded.io() };
    defer client.deinit();

    var pinned_repos = std.ArrayList(Project).empty;
    defer pinned_repos.deinit(allocator);

    for (GITHUB_API_URLS) |url| {
        var aw = std.Io.Writer.Allocating.init(allocator);
        _ = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .headers = .{
                .user_agent = .{ .override = "nuhu.dev" },
            },
            .response_writer = &aw.writer,
        });

        const response_text = aw.written();
        const prs = try filterPinnedRepos(allocator, response_text);
        try pinned_repos.appendSlice(allocator, prs);
    }

    return try pinned_repos.toOwnedSlice(allocator);
}

fn filterPinnedRepos(allocator: std.mem.Allocator, json_text: []const u8) ![]Project {
    const parsed = try std.json.parseFromSlice([]GitHubRepo, allocator, json_text, .{ .ignore_unknown_fields = true });
    const all_repos = parsed.value;

    const projects = try allocator.alloc(Project, PINNED_REPOS.len);
    var count: usize = 0;

    // Iterate pinned names in order, find matching repo from API response
    for (PINNED_REPOS) |pinned_name| {
        for (all_repos) |repo| {
            if (std.mem.eql(u8, repo.name, pinned_name)) {
                projects[count] = .{
                    .name = repo.name,
                    .description = repo.description orelse "No description",
                    .language = repo.language orelse "Unknown",
                    .stars = repo.stargazers_count,
                    .forks = repo.forks_count,
                    .url = repo.html_url,
                };
                count += 1;
                break;
            }
        }
    }

    return projects[0..count];
}

const GitHubRepo = struct {
    name: []const u8,
    description: ?[]const u8,
    html_url: []const u8,
    stargazers_count: u32,
    forks_count: u32,
    language: ?[]const u8,
};

const std = @import("std");
const zx_site_mod = @import("zx_site_mod");

const HASHNODE_GQL_URL = "https://gql.hashnode.com";
const HASHNODE_API_KEY = "YOUR_HASHNODE_API_KEY";

const GetPostError = error{ FailedToFetchPosts, FailedToParsePosts, OutOfMemory, PostNotFound };

pub fn getPosts(allocator: std.mem.Allocator, io: std.Io) GetPostError![]Post {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const get_posts_query = @embedFile("queries/get_posts.gql");

    var aw = std.Io.Writer.Allocating.init(allocator);

    _ = client.fetch(.{
        .method = .POST,
        .location = .{ .url = HASHNODE_GQL_URL },
        .headers = std.http.Client.Request.Headers{
            .authorization = .{ .override = HASHNODE_API_KEY },
            .content_type = .{ .override = "application/json" },
        },
        .payload = try std.json.Stringify.valueAlloc(allocator, .{
            .query = get_posts_query,
        }, .{}),

        .response_writer = &aw.writer,
    }) catch |err| {
        std.log.err("Failed to fetch posts: {any}", .{err});
        return error.FailedToFetchPosts;
    };

    const response_text = aw.written();
    return parsePostsFromJson(allocator, response_text) catch |err| {
        std.log.err("Failed to parse fetched posts: {any}", .{err});
        return error.FailedToParsePosts;
    };
}

fn parsePostsFromJson(allocator: std.mem.Allocator, json_text: []const u8) ![]Post {
    const parsed = try std.json.parseFromSlice(HashnodeResponse, allocator, json_text, .{});
    // defer parsed.deinit();

    const parsed_value: HashnodeResponse = parsed.value;
    const post_edges = parsed_value.data.publication.posts.edges;
    const posts = try allocator.alloc(Post, post_edges.len);

    for (posts, 0..) |*post_node, i| {
        const post = post_edges[i].node;
        post_node.* = .{
            .id = post.id,
            .title = post.title,
            .brief = post.brief,
            .url = post.url,
            .slug = post.slug,
            .publishedAt = post.publishedAt,
            .readTimeInMinutes = post.readTimeInMinutes,
            .views = post.views,
            .subtitle = post.subtitle,
            .coverImage = if (post.coverImage) |img| img.url else null,
            .content = null,
            .author = .{
                .name = post.author.name,
                .username = null,
                .profilePicture = null,
            },
        };
    }

    return posts;
}

pub fn getPostBySlug(allocator: std.mem.Allocator, io: std.Io, slug: []const u8) GetPostError!Post {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const get_post_query = @embedFile("queries/get_post.gql");

    var aw = std.Io.Writer.Allocating.init(allocator);

    _ = client.fetch(.{
        .method = .POST,
        .location = .{ .url = HASHNODE_GQL_URL },
        .headers = std.http.Client.Request.Headers{
            .authorization = .{ .override = HASHNODE_API_KEY },
            .content_type = .{ .override = "application/json" },
        },
        .payload = try std.json.Stringify.valueAlloc(allocator, .{
            .query = get_post_query,
            .variables = .{
                .slug = slug,
                .host = "blog.nurulhudaapon.com",
            },
        }, .{}),

        .response_writer = &aw.writer,
    }) catch |err| {
        std.log.err("Failed to fetch post: {any}", .{err});
        return error.FailedToFetchPosts;
    };

    const response_text = aw.written();
    return parsePostFromJson(allocator, response_text);
}

fn parsePostFromJson(allocator: std.mem.Allocator, json_text: []const u8) GetPostError!Post {
    const parsed = std.json.parseFromSlice(SinglePostResponse, allocator, json_text, .{}) catch |err| {
        std.log.err("Failed to parse post JSON: {any}", .{err});
        return error.FailedToParsePosts;
    };
    defer parsed.deinit();

    const parsed_value: SinglePostResponse = parsed.value;
    const post_data = parsed_value.data.publication.post orelse return error.PostNotFound;

    return .{
        .id = post_data.id,
        .title = post_data.title,
        .brief = post_data.brief,
        .url = post_data.url,
        .slug = post_data.slug,
        .publishedAt = post_data.publishedAt,
        .readTimeInMinutes = post_data.readTimeInMinutes,
        .views = post_data.views,
        .subtitle = post_data.subtitle,
        .coverImage = if (post_data.coverImage) |img| img.url else null,
        .content = if (post_data.content) |content| content.html else null,
        .author = .{
            .name = post_data.author.name,
            .username = post_data.author.username,
            .profilePicture = post_data.author.profilePicture,
        },
    };
}

pub const Post = struct {
    id: []const u8,
    title: []const u8,
    brief: []const u8,
    url: []const u8,
    slug: []const u8,
    publishedAt: []const u8,
    readTimeInMinutes: u32,
    views: u32,
    subtitle: ?[]const u8,
    coverImage: ?[]const u8,
    content: ?[]const u8,
    author: struct {
        name: []const u8,
        username: ?[]const u8,
        profilePicture: ?[]const u8,
    },
};

pub const HashnodeResponse = struct {
    data: struct {
        publication: struct {
            isTeam: bool,
            title: []const u8,
            posts: struct {
                edges: []struct {
                    node: struct {
                        id: []const u8,
                        coverImage: ?struct {
                            url: []const u8,
                        },
                        publishedAt: []const u8,
                        readTimeInMinutes: u32,
                        slug: []const u8,
                        subtitle: ?[]const u8,
                        views: u32,
                        title: []const u8,
                        brief: []const u8,
                        url: []const u8,
                        author: struct {
                            name: []const u8,
                        },
                    },
                },
            },
        },
    },
};

pub const SinglePostResponse = struct {
    data: struct {
        publication: struct {
            post: ?struct {
                id: []const u8,
                coverImage: ?struct {
                    url: []const u8,
                },
                publishedAt: []const u8,
                readTimeInMinutes: u32,
                slug: []const u8,
                subtitle: ?[]const u8,
                views: u32,
                title: []const u8,
                brief: []const u8,
                url: []const u8,
                content: ?struct {
                    html: []const u8,
                    markdown: []const u8,
                },
                author: struct {
                    name: []const u8,
                    username: ?[]const u8,
                    profilePicture: ?[]const u8,
                },
            },
        },
    },
};

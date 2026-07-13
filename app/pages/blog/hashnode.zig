const std = @import("std");

pub const cdn_prefix = "https://cdn.hashnode.com/res/hashnode/image/upload/";
pub const cdn_prefix_http = "http://cdn.hashnode.com/res/hashnode/image/upload/";
pub const local_prefix = "/images/hn/";

pub fn localizeUrl(allocator: std.mem.Allocator, url: []const u8) !?[]const u8 {
    const rest = stripCdnPrefix(url) orelse return null;
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ local_prefix, rest });
}

pub fn toStaticParam(allocator: std.mem.Allocator, url: []const u8) !?[]const u8 {
    if (std.mem.startsWith(u8, url, local_prefix)) {
        return try std.fmt.allocPrint(allocator, "hn/{s}", .{url[local_prefix.len..]});
    }
    const rest = stripCdnPrefix(url) orelse return null;
    return try std.fmt.allocPrint(allocator, "hn/{s}", .{rest});
}

pub fn stripCdnPrefix(url: []const u8) ?[]const u8 {
    const rest = if (std.mem.startsWith(u8, url, cdn_prefix))
        url[cdn_prefix.len..]
    else if (std.mem.startsWith(u8, url, cdn_prefix_http))
        url[cdn_prefix_http.len..]
    else
        return null;

    var end = rest.len;
    if (std.mem.indexOfAny(u8, rest, "?#")) |idx| end = idx;
    while (end > 0 and (rest[end - 1] == '.' or rest[end - 1] == ',' or rest[end - 1] == ';')) {
        end -= 1;
    }
    if (end == 0) return null;
    return rest[0..end];
}

pub fn collectStaticParamPaths(allocator: std.mem.Allocator, sources: []const []const u8) ![][]const u8 {
    var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |p| allocator.free(p);
        out.deinit(allocator);
    }

    for (sources) |source| {
        var start: usize = 0;
        while (start < source.len) {
            const https_at = std.mem.indexOfPos(u8, source, start, cdn_prefix);
            const http_at = std.mem.indexOfPos(u8, source, start, cdn_prefix_http);
            const abs = pickEarlier(https_at, http_at) orelse break;
            const prefix_len: usize = if (https_at != null and abs == https_at.?)
                cdn_prefix.len
            else
                cdn_prefix_http.len;

            var url_end = abs + prefix_len;
            while (url_end < source.len and !isUrlEnd(source[url_end])) : (url_end += 1) {}

            if (stripCdnPrefix(source[abs..url_end])) |rest| {
                const key = try std.fmt.allocPrint(allocator, "hn/{s}", .{rest});
                const gop = try seen.getOrPut(allocator, key);
                if (gop.found_existing) {
                    allocator.free(key);
                } else {
                    gop.key_ptr.* = key;
                    try out.append(allocator, key);
                }
            }
            start = url_end;
        }
    }

    seen.clearRetainingCapacity();
    return try out.toOwnedSlice(allocator);
}

fn pickEarlier(a: ?usize, b: ?usize) ?usize {
    if (a == null) return b;
    if (b == null) return a;
    return @min(a.?, b.?);
}

fn isUrlEnd(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r', ')', '"', '\'', '<', '>', ']' => true,
        else => false,
    };
}

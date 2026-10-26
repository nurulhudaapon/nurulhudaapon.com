const std = @import("std");

pub const protocol_version_header = "MCP-Protocol-Version";
pub const session_id_header = "Mcp-Session-Id";

pub const AuthChallenge = struct {
    resource_metadata_url: []const u8,
    scope: ?[]const u8 = null,
    realm: []const u8 = "mcp",
};

pub fn wwwAuthenticate(allocator: std.mem.Allocator, challenge: AuthChallenge) ![]u8 {
    if (challenge.scope) |scope| {
        return std.fmt.allocPrint(allocator, "Bearer realm=\"{s}\", resource_metadata=\"{s}\", scope=\"{s}\"", .{
            challenge.realm,
            challenge.resource_metadata_url,
            scope,
        });
    }
    return std.fmt.allocPrint(allocator, "Bearer realm=\"{s}\", resource_metadata=\"{s}\"", .{
        challenge.realm,
        challenge.resource_metadata_url,
    });
}

pub fn extractBearer(authorization: ?[]const u8) ?[]const u8 {
    const h = authorization orelse return null;
    const trimmed = std.mem.trim(u8, h, " \t");
    if (trimmed.len < 7 or !std.ascii.eqlIgnoreCase(trimmed[0..6], "Bearer")) return null;
    const rest = std.mem.trimStart(u8, trimmed[6..], " \t");
    return if (rest.len == 0) null else rest;
}

pub fn constantTimeEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |x, y| diff |= x ^ y;
    return diff == 0;
}

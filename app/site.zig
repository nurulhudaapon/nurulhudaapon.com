pub const url = "https://nurulhudaapon.com";

// The canonical origin, except when served on this machine (`zig build dev`,
// `wrangler dev`), where links and sign-in callbacks have to stay local. Only a
// strict loopback host is honoured, so a forged Host header can't point a
// response anywhere else.
pub fn origin(request: zx.server.Request) []const u8 {
    const host = request.headers.get("host") orelse return url;
    if (!isLoopback(host)) return url;
    return request.arena.print("http://{s}", .{host}) catch url;
}

fn isLoopback(host: []const u8) bool {
    for ([_][]const u8{ "localhost", "127.0.0.1", "[::1]" }) |name| {
        if (!std.mem.startsWith(u8, host, name)) continue;
        const port = host[name.len..];
        if (port.len == 0) return true;
        if (port[0] != ':' or port.len == 1 or port.len > 6) return false;
        for (port[1..]) |c| if (!std.ascii.isDigit(c)) return false;
        return true;
    }
    return false;
}

test isLoopback {
    try std.testing.expect(isLoopback("localhost"));
    try std.testing.expect(isLoopback("localhost:8787"));
    try std.testing.expect(isLoopback("127.0.0.1:3000"));
    try std.testing.expect(isLoopback("[::1]:3000"));
    try std.testing.expect(!isLoopback("nurulhudaapon.com"));
    try std.testing.expect(!isLoopback("localhost.evil.com"));
    try std.testing.expect(!isLoopback("localhost:@evil.com"));
    try std.testing.expect(!isLoopback("localhost:"));
    try std.testing.expect(!isLoopback("127.0.0.1.nip.io"));
}

const std = @import("std");
const zx = @import("zx");

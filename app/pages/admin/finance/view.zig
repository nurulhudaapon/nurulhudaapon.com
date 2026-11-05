const std = @import("std");
const zx = @import("zx");
const finance = @import("../../../finance.zig");

pub fn changed() void {
    finance.history.record() catch |err| zx.log.warn("admin: record finance history failed: {any}", .{err});
    // Drops the `@caching="15s:finance_*"` components and the edge page cache, keyed by pathname.
    _ = zx.cache.scoped(.cmp).deletePrefix("cmp:finance") catch 0;
    zx.kv.scoped(.@"page-cache").delete("/admin/finance") catch {};
}

pub fn accountHref(arena: std.mem.Allocator, id: i64) []const u8 {
    return arena.print("/admin/finance/accounts/{d}", .{id}) catch "/admin/finance/accounts";
}

pub fn editHref(arena: std.mem.Allocator, id: i64) []const u8 {
    return arena.print("/admin/finance/accounts/{d}/edit", .{id}) catch "/admin/finance/accounts";
}

pub fn signedMoney(arena: std.mem.Allocator, amount: f64, currency: []const u8) []const u8 {
    return arena.print("{s}{s}", .{ sign(amount), finance.format.money(arena, amount, currency) }) catch "";
}

pub fn signedPct(arena: std.mem.Allocator, value: f64) []const u8 {
    return arena.print("{s}{s}", .{ sign(value), finance.format.pct(arena, value) }) catch "";
}

fn sign(value: f64) []const u8 {
    return if (value >= 0) "+" else "";
}

pub fn accountCount(arena: std.mem.Allocator, n: anytype) []const u8 {
    return arena.print("{d} account{s}", .{ n, if (n == 1) "" else "s" }) catch "";
}

pub fn barWidth(arena: std.mem.Allocator, pct: f64) []const u8 {
    return arena.print("width:{d:.1}%", .{@max(0, @min(pct, 100))}) catch "width:0%";
}

pub fn isActivationKey(e: *zx.client.Event.Stateful) bool {
    const key = e.key() orelse return false;
    return std.mem.eql(u8, key, "Enter") or std.mem.eql(u8, key, " ");
}

pub fn formInt(fd: anytype, name: []const u8) !i64 {
    return std.fmt.parseInt(i64, fd.get(name) orelse "0", 10) catch error.InvalidName;
}

const std = @import("std");
const fx = @import("fx.zig");
const number = @import("number.zig");

pub fn money(arena: std.mem.Allocator, amount: f64, currency: []const u8) []const u8 {
    const abs = @abs(amount);
    const sign: []const u8 = if (amount < 0) "-" else "";
    if (fx.isMetal(currency)) {
        if (@abs(abs - @round(abs)) < 0.0005)
            return arena.print("{s}{d} g", .{ sign, @as(i64, @intFromFloat(@round(abs))) }) catch "";
        return arena.print("{s}{d:.2} g", .{ sign, abs }) catch "";
    }
    const whole: u64 = @intFromFloat(@floor(abs));
    var frac: u64 = @intFromFloat(@round((abs - @floor(abs)) * 100.0));
    if (frac >= 100) frac = 99;
    if (std.ascii.eqlIgnoreCase(currency, "BDT")) {
        const digits = number.groupDigits(arena, whole, .south_asian);
        if (frac == 0) return arena.print("{s}৳{s}", .{ sign, digits }) catch "";
        return arena.print("{s}৳{s}.{d:0>2}", .{ sign, digits, frac }) catch "";
    }
    const digits = number.groupDigits(arena, whole, .western);
    if (std.ascii.eqlIgnoreCase(currency, "JPY"))
        return arena.print("{s}¥{s}", .{ sign, digits }) catch "";
    if (std.ascii.eqlIgnoreCase(currency, "USD"))
        return arena.print("{s}${s}.{d:0>2}", .{ sign, digits, frac }) catch "";
    return arena.print("{s}{s} {s}.{d:0>2}", .{ sign, currency, digits, frac }) catch "";
}

pub fn pct(arena: std.mem.Allocator, value: f64) []const u8 {
    const rounded: i64 = @intFromFloat(@round(value * 10.0));
    return arena.print("{d}.{d}%", .{ @divTrunc(rounded, 10), @mod(@abs(rounded), 10) }) catch "";
}

pub fn qty(arena: std.mem.Allocator, value: f64) []const u8 {
    const sign: []const u8 = if (value < 0) "-" else "";
    const abs = @abs(value);
    if (@abs(abs - @round(abs)) < 0.0001)
        return arena.print("{s}{s}", .{ sign, number.groupDigits(arena, @intFromFloat(@round(abs)), .western) }) catch "";
    const whole: u64 = @intFromFloat(@floor(abs));
    const frac: u64 = @min(9999, @as(u64, @intFromFloat(@round((abs - @floor(abs)) * 10000.0))));
    return arena.print("{s}{s}.{d:0>4}", .{ sign, number.groupDigits(arena, whole, .western), frac }) catch "";
}

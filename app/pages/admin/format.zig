const std = @import("std");
const zx = @import("zx");
const slots = @import("../schedule/slots.zig");

fn now() i64 {
    return std.Io.Timestamp.now(zx.io(), .real).toSeconds();
}

/// `raw` is unix seconds as text.
pub fn ago(arena: std.mem.Allocator, raw: []const u8) []const u8 {
    const ts = std.fmt.parseInt(i64, raw, 10) catch return raw;
    const delta = now() - ts;
    if (delta < 60) return "just now";
    if (delta < std.time.s_per_hour) return std.fmt.allocPrint(arena, "{d}m ago", .{@divTrunc(delta, 60)}) catch raw;
    if (delta < std.time.s_per_day) return std.fmt.allocPrint(arena, "{d}h ago", .{@divTrunc(delta, std.time.s_per_hour)}) catch raw;
    if (delta < 30 * std.time.s_per_day) return std.fmt.allocPrint(arena, "{d}d ago", .{@divTrunc(delta, std.time.s_per_day)}) catch raw;
    return date(arena, ts);
}

pub fn until(arena: std.mem.Allocator, unix: i64) []const u8 {
    const delta = unix - now();
    if (delta <= 0) return "now";
    if (delta < std.time.s_per_hour) return std.fmt.allocPrint(arena, "in {d}m", .{@divTrunc(delta, 60) + 1}) catch "";
    if (delta < std.time.s_per_day) return std.fmt.allocPrint(arena, "in {d}h", .{@divTrunc(delta, std.time.s_per_hour)}) catch "";
    return std.fmt.allocPrint(arena, "in {d}d", .{@divTrunc(delta, std.time.s_per_day)}) catch "";
}

pub fn date(arena: std.mem.Allocator, unix: i64) []const u8 {
    return slots.formatDate(arena, unix, slots.config.utc_offset_s) catch "";
}

pub fn timeRange(arena: std.mem.Allocator, start: i64, end: i64) []const u8 {
    const offset = slots.config.utc_offset_s;
    const a = slots.formatTime(arena, start, offset) catch "";
    const b = slots.formatTime(arena, end, offset) catch "";
    return std.fmt.allocPrint(arena, "{s} - {s}", .{ a, b }) catch "";
}

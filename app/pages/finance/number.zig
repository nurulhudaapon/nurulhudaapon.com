// Kept free of `zx` so it unit-tests standalone.

pub const Grouping = enum {
    // 1,234,567
    western,
    // 12,34,567 (lakh/crore), the local convention for taka
    south_asian,
};

pub fn groupDigits(arena: std.mem.Allocator, n: u64, grouping: Grouping) []const u8 {
    var raw_buf: [20]u8 = undefined;
    const raw = std.fmt.bufPrint(&raw_buf, "{d}", .{n}) catch return "";
    if (raw.len <= 3) return arena.dupe(u8, raw) catch "";

    var out: std.ArrayList(u8) = .empty;
    const head_len = raw.len - 3;
    const step: usize = if (grouping == .south_asian) 2 else 3;
    var first = head_len % step;
    if (first == 0) first = step;
    out.appendSlice(arena, raw[0..first]) catch return raw;
    var i = first;
    while (i < head_len) : (i += step) {
        out.append(arena, ',') catch return raw;
        out.appendSlice(arena, raw[i .. i + step]) catch return raw;
    }
    out.append(arena, ',') catch return raw;
    out.appendSlice(arena, raw[head_len..]) catch return raw;
    return out.items;
}

test groupDigits {
    const arena = std.testing.allocator;
    var state: std.heap.ArenaAllocator = .init(arena);
    defer state.deinit();
    const a = state.allocator();
    try std.testing.expectEqualStrings("0", groupDigits(a, 0, .western));
    try std.testing.expectEqualStrings("999", groupDigits(a, 999, .south_asian));
    try std.testing.expectEqualStrings("1,000", groupDigits(a, 1000, .western));
    try std.testing.expectEqualStrings("1,234,567", groupDigits(a, 1234567, .western));
    try std.testing.expectEqualStrings("1,000", groupDigits(a, 1000, .south_asian));
    try std.testing.expectEqualStrings("12,34,567", groupDigits(a, 1234567, .south_asian));
    try std.testing.expectEqualStrings("1,23,45,678", groupDigits(a, 12345678, .south_asian));
}

const std = @import("std");

// Just enough CBOR (RFC 8949) to read WebAuthn attestation objects and COSE keys.
// Authenticators only emit definite lengths, so indefinite ones are rejected.
const Cbor = @This();

data: []const u8,
pos: usize = 0,

pub const Item = union(enum) {
    int: i64,
    bytes: []const u8,
    text: []const u8,
    // Containers carry their element (or pair) count; the elements follow.
    array: usize,
    map: usize,
    simple: u8,
};

// Bounds `skip`, so hostile nesting can't exhaust the stack.
const max_depth = 16;

pub fn next(r: *Cbor) !Item {
    const head = try r.byte();
    const arg = try r.argument(@truncate(head));
    return switch (head >> 5) {
        0 => .{ .int = std.math.cast(i64, arg) orelse return error.InvalidCbor },
        1 => .{ .int = -1 - (std.math.cast(i64, arg) orelse return error.InvalidCbor) },
        2 => .{ .bytes = try r.take(arg) },
        3 => .{ .text = try r.take(arg) },
        4 => .{ .array = std.math.cast(usize, arg) orelse return error.InvalidCbor },
        5 => .{ .map = std.math.cast(usize, arg) orelse return error.InvalidCbor },
        7 => .{ .simple = std.math.cast(u8, arg) orelse return error.InvalidCbor },
        else => error.InvalidCbor,
    };
}

pub fn expect(r: *Cbor, comptime tag: std.meta.Tag(Item)) !@FieldType(Item, @tagName(tag)) {
    const item = try r.next();
    return if (item == tag) @field(item, @tagName(tag)) else error.InvalidCbor;
}

pub fn skip(r: *Cbor) !void {
    return r.skipDepth(0);
}

fn skipDepth(r: *Cbor, depth: usize) !void {
    if (depth > max_depth) return error.InvalidCbor;
    switch (try r.next()) {
        .array => |n| for (0..n) |_| try r.skipDepth(depth + 1),
        .map => |n| for (0..n * 2) |_| try r.skipDepth(depth + 1),
        else => {},
    }
}

fn byte(r: *Cbor) !u8 {
    return (try r.take(1))[0];
}

fn take(r: *Cbor, len: u64) ![]const u8 {
    if (len > r.data.len - r.pos) return error.UnexpectedEnd;
    const n: usize = @intCast(len);
    defer r.pos += n;
    return r.data[r.pos..][0..n];
}

fn argument(r: *Cbor, info: u5) !u64 {
    return switch (info) {
        0...23 => info,
        24 => try r.byte(),
        25 => std.mem.readInt(u16, (try r.take(2))[0..2], .big),
        26 => std.mem.readInt(u32, (try r.take(4))[0..4], .big),
        27 => std.mem.readInt(u64, (try r.take(8))[0..8], .big),
        else => error.InvalidCbor,
    };
}

test next {
    // {1: 2, -3: h'0102', "a": [true]}
    var r: Cbor = .{ .data = &.{ 0xa3, 0x01, 0x02, 0x22, 0x42, 0x01, 0x02, 0x61, 'a', 0x81, 0xf5 } };
    try std.testing.expectEqual(3, try r.expect(.map));
    try std.testing.expectEqual(1, try r.expect(.int));
    try std.testing.expectEqual(2, try r.expect(.int));
    try std.testing.expectEqual(-3, try r.expect(.int));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, try r.expect(.bytes));
    try std.testing.expectEqualStrings("a", try r.expect(.text));
    try r.skip();
    try std.testing.expectEqual(r.data.len, r.pos);
}

test "rejects truncated, indefinite and deeply nested items" {
    var short: Cbor = .{ .data = &.{ 0x42, 0x01 } };
    try std.testing.expectError(error.UnexpectedEnd, short.next());
    var indefinite: Cbor = .{ .data = &.{0x9f} };
    try std.testing.expectError(error.InvalidCbor, indefinite.next());
    var deep: Cbor = .{ .data = &(@as([32]u8, @splat(0x81)) ++ [_]u8{0x00}) };
    try std.testing.expectError(error.InvalidCbor, deep.skip());
    var wrong: Cbor = .{ .data = &.{0x01} };
    try std.testing.expectError(error.InvalidCbor, wrong.expect(.bytes));
}

const std = @import("std");

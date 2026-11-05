const std = @import("std");
const zx = @import("zx");

pub const Class = struct { name: []const u8 };

pub fn list(arena: std.mem.Allocator) ![]const Class {
    return try zx.db.rows(arena, Class,
        \\SELECT name FROM asset_classes ORDER BY sort_order, name COLLATE NOCASE
    , .{});
}

pub fn exists(arena: std.mem.Allocator, name: []const u8) !bool {
    const row = try zx.db.row(arena, struct { ok: i64 },
        \\SELECT 1 AS ok FROM asset_classes WHERE name = ?1 LIMIT 1
    , .{name});
    return row != null;
}

pub fn ensure(arena: std.mem.Allocator, name: []const u8) !void {
    if (try exists(arena, name)) return;
    const order_row = try zx.db.row(arena, struct { n: i64 },
        \\SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM asset_classes
    , .{});
    _ = try zx.db.run(
        \\INSERT OR IGNORE INTO asset_classes (name, sort_order) VALUES (?1, ?2)
    , .{ name, if (order_row) |r| r.n else 100 });
}

// Maps broker asset categories to asset classes, case-insensitively.
pub const Aliases = struct {
    map: std.StringHashMapUnmanaged([]const u8),

    pub fn load(arena: std.mem.Allocator) !Aliases {
        var map: std.StringHashMapUnmanaged([]const u8) = .empty;
        const rows = try zx.db.rows(arena, struct { alias: []const u8, asset_class: []const u8 },
            \\SELECT alias, asset_class FROM asset_class_aliases
        , .{});
        for (rows) |r| try map.put(arena, r.alias, r.asset_class);
        return .{ .map = map };
    }

    pub fn resolve(self: Aliases, name: []const u8) []const u8 {
        var it = self.map.iterator();
        while (it.next()) |kv| {
            if (std.ascii.eqlIgnoreCase(kv.key_ptr.*, name)) return kv.value_ptr.*;
        }
        return "Alternatives";
    }
};

const std = @import("std");
const zx = @import("zx");

const Migration = struct { name: []const u8, sql: []const u8 };

const migrations = [_]Migration{
    .{ .name = "0001_init.sql", .sql = @embedFile("migrations/0001_init.sql") },
    .{ .name = "0002_init_data.sql", .sql = @embedFile("migrations/0002_init_data.sql") },
    .{ .name = "0003_bookings.sql", .sql = @embedFile("migrations/0003_bookings.sql") },
    .{ .name = "0004_admin.sql", .sql = @embedFile("migrations/0004_admin.sql") },
};

/// Local only; uses wrangler's `d1_migrations` table so both track the same files.
pub fn run() !void {
    if (zx.platform.isWasm()) return;

    _ = try zx.db.run(
        \\CREATE TABLE IF NOT EXISTS d1_migrations (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT UNIQUE,
        \\  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        \\)
    , .{});

    var arena_state: std.heap.ArenaAllocator = .init(zx.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    for (migrations) |m| {
        const applied = try zx.db.row(arena, struct { ok: i64 },
            \\SELECT 1 AS ok FROM d1_migrations WHERE name = ?1
        , .{m.name});
        if (applied != null) continue;

        try execScript(m.sql);
        _ = try zx.db.run("INSERT INTO d1_migrations (name) VALUES (?1)", .{m.name});
        std.log.info("migration applied: {s}", .{m.name});
    }
}

fn execScript(sql: []const u8) !void {
    var it = std.mem.splitScalar(u8, sql, ';');
    while (it.next()) |raw| {
        const stmt = std.mem.trim(u8, raw, " \t\r\n");
        if (stmt.len == 0 or isCommentOnly(stmt)) continue;
        _ = zx.db.run(stmt, .{}) catch |err| {
            std.log.err("migration statement failed: {s}\n  sql: {s}", .{ @errorName(err), stmt });
            return err;
        };
    }
}

fn isCommentOnly(stmt: []const u8) bool {
    var lines = std.mem.splitScalar(u8, stmt, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (!std.mem.startsWith(u8, trimmed, "--")) return false;
    }
    return true;
}

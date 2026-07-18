const std = @import("std");
const zx = @import("zx");

pub fn run() !void {
    if (zx.platform.isWasm()) return;

    const migrations = [_][]const u8{
        @embedFile("migrations/0001_init.sql"),
        @embedFile("migrations/0002_init_data.sql"),
    };

    for (migrations) |sql| {
        try execScript(sql);
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


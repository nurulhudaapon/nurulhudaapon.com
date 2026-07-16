const std = @import("std");
const zx = @import("zx");

pub const Question = struct {
    id: i64,
    question: []const u8,
    answer: ?[]const u8 = null,
    email: ?[]const u8 = null,
    visitor_id: []const u8,
    visitor_json: ?[]const u8 = null,
    created_at: []const u8,
    seen: bool = false,
    seen_at: ?[]const u8 = null,
};

pub fn ensureSchema() !void {
    _ = try zx.db.run(
        \\CREATE TABLE IF NOT EXISTS questions (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  question TEXT NOT NULL,
        \\  answer TEXT,
        \\  email TEXT,
        \\  visitor_id TEXT NOT NULL,
        \\  visitor_json TEXT,
        \\  created_at TEXT NOT NULL,
        \\  seen INTEGER NOT NULL DEFAULT 0,
        \\  seen_at TEXT,
        \\  deleted INTEGER NOT NULL DEFAULT 0
        \\)
    , .empty);
    _ = try zx.db.run(
        \\CREATE TABLE IF NOT EXISTS admin (
        \\  credential TEXT PRIMARY KEY NOT NULL
        \\)
    , .empty);
}

pub fn isValidAdmin(allocator: std.mem.Allocator, credential: ?[]const u8) !bool {
    const provided = credential orelse return false;
    if (provided.len == 0) return false;
    const hit = try zx.db.row(allocator, struct { ok: i64 },
        \\SELECT 1 AS ok FROM admin WHERE credential = ?1 LIMIT 1
    , .{provided});
    return hit != null;
}

pub fn insertQuestion(
    allocator: std.mem.Allocator,
    question: []const u8,
    email: []const u8,
    visitor_id: []const u8,
    visitor_json: []const u8,
) !void {
    const created_at = try nowStamp(allocator);
    _ = try zx.db.run(
        \\INSERT INTO questions (question, email, visitor_id, visitor_json, created_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5)
    , .{ question, email, visitor_id, visitor_json, created_at });
}

pub fn setAnswer(id: i64, answer: []const u8) !void {
    _ = try zx.db.run(
        \\UPDATE questions SET answer = ?1, seen = 0, seen_at = NULL WHERE id = ?2 AND deleted = 0
    , .{ answer, id });
}

pub fn softDelete(id: i64) !void {
    _ = try zx.db.run(
        \\UPDATE questions SET deleted = 1 WHERE id = ?1
    , .{id});
}

pub fn listForVisitor(allocator: std.mem.Allocator, visitor_id: []const u8) ![]const Question {
    return try zx.db.rows(allocator, Question,
        \\SELECT id, question, answer, email, visitor_id, visitor_json, created_at, seen, seen_at
        \\FROM questions
        \\WHERE visitor_id = ?1 AND deleted = 0
        \\ORDER BY id DESC
    , .{visitor_id});
}

pub fn listAll(allocator: std.mem.Allocator) ![]const Question {
    return try zx.db.rows(allocator, Question,
        \\SELECT id, question, answer, email, visitor_id, visitor_json, created_at, seen, seen_at
        \\FROM questions
        \\WHERE deleted = 0
        \\ORDER BY id DESC
    , .{});
}

pub fn markAnsweredSeen(allocator: std.mem.Allocator, visitor_id: []const u8) !void {
    const stamp = try nowStamp(allocator);
    _ = try zx.db.run(
        \\UPDATE questions
        \\SET seen = 1, seen_at = ?1
        \\WHERE visitor_id = ?2 AND deleted = 0 AND answer IS NOT NULL AND seen = 0
    , .{ stamp, visitor_id });
}

pub fn getById(allocator: std.mem.Allocator, id: i64) !?Question {
    return try zx.db.row(allocator, Question,
        \\SELECT id, question, answer, email, visitor_id, visitor_json, created_at, seen, seen_at
        \\FROM questions
        \\WHERE id = ?1 AND deleted = 0
    , .{id});
}

fn nowStamp(allocator: std.mem.Allocator) ![]const u8 {
    const ts = std.Io.Timestamp.now(zx.io(), .real);
    const secs = @divTrunc(ts.nanoseconds, std.time.ns_per_s);
    return try std.fmt.allocPrint(allocator, "{d}", .{secs});
}

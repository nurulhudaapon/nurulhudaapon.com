const std = @import("std");
const zx = @import("zx");

pub const Question = struct {
    id: i64,
    question: []const u8,
    answer: ?[]const u8 = null,
    visitor_id: []const u8,
    created_at: []const u8,
    seen_at: ?[]const u8 = null,
};

pub fn isValidAdmin(allocator: std.mem.Allocator, credential: ?[]const u8) !bool {
    const provided = credential orelse return false;
    if (provided.len == 0) return false;
    const hit = try zx.db.row(allocator, struct { ok: i64 },
        \\SELECT 1 AS ok FROM credentials WHERE val = ?1 AND cat = 'admin' LIMIT 1
    , .{provided});
    return hit != null;
}

pub fn insertQuestion(
    question: []const u8,
    email: []const u8,
    visitor_id: []const u8,
    visitor_json: []const u8,
) !void {
    _ = try zx.db.run(
        \\INSERT INTO questions (question, email, visitor_id, visitor_json, created_at)
        \\VALUES (?1, ?2, ?3, ?4, CAST(unixepoch() AS TEXT))
    , .{ question, email, visitor_id, visitor_json });
}

pub fn setAnswer(id: i64, answer: []const u8) !void {
    _ = try zx.db.run(
        \\UPDATE questions SET answer = ?1, seen_at = NULL WHERE id = ?2 AND deleted = 0
    , .{ answer, id });
}

pub fn softDelete(id: i64) !void {
    _ = try zx.db.run(
        \\UPDATE questions SET deleted = 1 WHERE id = ?1
    , .{id});
}

pub fn listForVisitor(allocator: std.mem.Allocator, visitor_id: []const u8) ![]const Question {
    return try zx.db.rows(allocator, Question,
        \\SELECT id, question, answer, visitor_id, created_at, seen_at
        \\FROM questions
        \\WHERE visitor_id = ?1 AND deleted = 0
        \\ORDER BY id DESC
    , .{visitor_id});
}

pub fn listAll(allocator: std.mem.Allocator) ![]const Question {
    return try zx.db.rows(allocator, Question,
        \\SELECT id, question, answer, visitor_id, created_at, seen_at
        \\FROM questions
        \\WHERE deleted = 0
        \\ORDER BY id DESC
    , .{});
}

pub fn markAnsweredSeen(visitor_id: []const u8) !void {
    _ = try zx.db.run(
        \\UPDATE questions
        \\SET seen_at = CAST(unixepoch() AS TEXT)
        \\WHERE visitor_id = ?1 AND deleted = 0 AND answer IS NOT NULL AND seen_at IS NULL
    , .{visitor_id});
}

pub fn getById(allocator: std.mem.Allocator, id: i64) !?Question {
    return try zx.db.row(allocator, Question,
        \\SELECT id, question, answer, visitor_id, created_at, seen_at
        \\FROM questions
        \\WHERE id = ?1 AND deleted = 0
    , .{id});
}

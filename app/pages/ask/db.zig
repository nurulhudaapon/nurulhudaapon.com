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

pub fn insertQuestion(
    question: []const u8,
    visitor_id: []const u8,
    visitor_json: []const u8,
    ip_hash: []const u8,
) !i64 {
    const result = try zx.db.run(
        \\INSERT INTO questions (question, visitor_id, visitor_json, ip_hash, created_at)
        \\VALUES (?1, ?2, ?3, NULLIF(?4, ''), CAST(unixepoch() AS TEXT))
    , .{ question, visitor_id, visitor_json, ip_hash });
    return result.last_insert_id;
}

const max_daily_per_sender = 5;

pub const Gate = enum { ok, limited, duplicate };

// Looks at the last day, including deleted rows so deleting spam doesn't reset a limit.
pub fn gate(allocator: std.mem.Allocator, visitor_id: []const u8, ip_hash: []const u8, question: []const u8) !Gate {
    const row = try zx.db.row(allocator, struct { recent: i64, dupes: i64 },
        \\SELECT
        \\  (SELECT COUNT(*) FROM questions WHERE CAST(created_at AS INTEGER) > unixepoch() - 86400
        \\    AND (visitor_id = ?1 OR (?2 <> '' AND ip_hash = ?2))) AS recent,
        \\  (SELECT COUNT(*) FROM questions WHERE CAST(created_at AS INTEGER) > unixepoch() - 86400
        \\    AND question = ?3) AS dupes
    , .{ visitor_id, ip_hash, question });
    const r = row orelse return .ok;
    if (r.recent >= max_daily_per_sender) return .limited;
    if (r.dupes > 0) return .duplicate;
    return .ok;
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

pub const Filter = enum { unanswered, answered, all };

pub fn listFiltered(allocator: std.mem.Allocator, filter: Filter) ![]const Question {
    const select =
        \\SELECT id, question, answer, visitor_id, created_at, seen_at FROM questions WHERE deleted = 0
    ;
    return switch (filter) {
        .unanswered => zx.db.rows(allocator, Question, select ++ " AND answer IS NULL ORDER BY id DESC", .{}),
        .answered => zx.db.rows(allocator, Question, select ++ " AND answer IS NOT NULL ORDER BY id DESC", .{}),
        .all => listAll(allocator),
    };
}

pub const Counts = struct { unanswered: i64 = 0, answered: i64 = 0, all: i64 = 0 };

pub fn counts(allocator: std.mem.Allocator) Counts {
    const row = zx.db.row(allocator, Counts,
        \\SELECT COALESCE(SUM(answer IS NULL), 0) AS unanswered,
        \\  COALESCE(SUM(answer IS NOT NULL), 0) AS answered, COUNT(*) AS "all"
        \\FROM questions WHERE deleted = 0
    , .{}) catch return .{};
    return row orelse .{};
}

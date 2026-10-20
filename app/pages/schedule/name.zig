const std = @import("std");

/// Words people often type before the name they go by, compared
/// case-insensitively with any trailing dot removed.
const prefixes = south_asian ++ honorifics;

/// "Md Nurul Huda" and "Mohammad Rahim" go by Nurul and Rahim.
const south_asian = [_][]const u8{ "md", "mohd", "mohammad", "mohammed", "muhammad", "muhammed", "mst", "mosammat", "mosamat", "most", "sk", "sheikh", "shaikh" };

const honorifics = [_][]const u8{ "mr", "mrs", "ms", "miss", "mx", "sir", "madam", "dame", "dr", "prof", "professor", "engr", "eng", "rev", "hon", "capt", "lt", "col", "maj", "gen", "sgt", "adv" };

/// The name to greet someone by: "Md. Nurul Huda" is "Nurul". Falls back to the
/// whole name when every word is a prefix.
pub fn firstName(arena: std.mem.Allocator, full: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, full, " \t\r\n");
    var words = std.mem.tokenizeAny(u8, trimmed, " \t\r\n,");
    while (words.next()) |word| {
        if (isPrefix(word) or isInitials(word)) continue;
        return titleCase(arena, word);
    }
    return trimmed;
}

fn isPrefix(word: []const u8) bool {
    const bare = std.mem.trimEnd(u8, word, ".");
    for (prefixes) |p| if (std.ascii.eqlIgnoreCase(bare, p)) return true;
    return false;
}

/// "J", "J." or "A.K.M.": letters each followed by a dot, or a lone letter.
fn isInitials(word: []const u8) bool {
    if (word.len == 1) return std.ascii.isAlphabetic(word[0]);
    if (std.mem.indexOfScalar(u8, word, '.') == null) return false;
    var parts = std.mem.tokenizeScalar(u8, word, '.');
    while (parts.next()) |part| if (part.len != 1) return false;
    return true;
}

/// "nurul" and "NURUL" become "Nurul"; mixed case like "McKay" is kept.
fn titleCase(arena: std.mem.Allocator, word: []const u8) []const u8 {
    var has_lower = false;
    var has_upper = false;
    for (word) |ch| {
        if (std.ascii.isLower(ch)) has_lower = true;
        if (std.ascii.isUpper(ch)) has_upper = true;
    }
    if (has_lower and has_upper) return word;
    const out = arena.dupe(u8, word) catch return word;
    for (out, 0..) |*ch, i| ch.* = if (i == 0) std.ascii.toUpper(ch.*) else std.ascii.toLower(ch.*);
    return out;
}

test firstName {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][2][]const u8{
        .{ "Nurul Huda", "Nurul" },
        .{ "Md. Nurul Huda", "Nurul" },
        .{ "MD NURUL HUDA", "Nurul" },
        .{ "Mohammad Rahim Uddin", "Rahim" },
        .{ "Mst. Ayesha Akter", "Ayesha" },
        .{ "Dr. Jane Smith", "Jane" },
        .{ "Mr John", "John" },
        .{ "A.K.M. Fazlul Haque", "Fazlul" },
        .{ "J. Smith", "Smith" },
        .{ "  ada  ", "Ada" },
        .{ "Jean-Luc Picard", "Jean-Luc" },
        .{ "McKay Lee", "McKay" },
        .{ "Md.", "Md." },
        .{ "Nurul", "Nurul" },
        .{ "Mdina Ali", "Mdina" },
    }) |case| try std.testing.expectEqualStrings(case[1], firstName(a, case[0]));
}

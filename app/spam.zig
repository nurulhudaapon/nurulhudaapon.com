const std = @import("std");

const proof_salt = "nurulhudaapon.com/ask-proof/";
// Proofs rotate hourly and the current and previous window are accepted.
const proof_window_s: i64 = 3600;

// Salted so stored values aren't a direct lookup of the address. Empty without
// the Cloudflare header (local dev), which disables per-IP limits.
pub fn ipHash(arena: std.mem.Allocator, ip: ?[]const u8) []const u8 {
    const addr = ip orelse return "";
    if (addr.len == 0) return "";
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("nurulhudaapon.com/");
    hasher.update(addr);
    const digest = hasher.finalResult();
    return arena.print("{x}", .{digest[0..16].*}) catch "";
}

// Minted on render and carried in component state, so a submit without a fresh
// page render can't produce it.
pub fn proof(visitor_id: []const u8, now: i64) u32 {
    return proofAt(visitor_id, bucket(now));
}

pub fn validProof(visitor_id: []const u8, submitted: u32, now: i64) bool {
    if (visitor_id.len == 0) return false;
    const b = bucket(now);
    return proofAt(visitor_id, b) == submitted or
        (b > 0 and proofAt(visitor_id, b - 1) == submitted);
}

fn bucket(unix: i64) u64 {
    return @intCast(@divFloor(unix, proof_window_s));
}

fn proofAt(visitor_id: []const u8, b: u64) u32 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(proof_salt);
    hasher.update(visitor_id);
    hasher.update(std.mem.asBytes(&b));
    const digest = hasher.finalResult();
    return std.mem.readInt(u32, digest[0..4], .big);
}

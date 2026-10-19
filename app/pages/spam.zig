const std = @import("std");
const zx = @import("zx");

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
    return std.fmt.allocPrint(arena, "{x}", .{digest[0..16].*}) catch "";
}

// Minted on render and carried in component state, so a submit without a fresh
// page render can't produce it.
pub fn formProof(visitor_id: []const u8) u32 {
    return proofNumber(visitor_id, timeBucket(nowUnix()));
}

pub fn validFormProof(visitor_id: []const u8, submitted: u32) bool {
    if (visitor_id.len == 0) return false;
    const bucket = timeBucket(nowUnix());
    return proofNumber(visitor_id, bucket) == submitted or
        (bucket > 0 and proofNumber(visitor_id, bucket - 1) == submitted);
}

fn nowUnix() i64 {
    return std.Io.Timestamp.now(zx.io(), .real).toSeconds();
}

fn timeBucket(unix: i64) u64 {
    return @intCast(@divFloor(unix, proof_window_s));
}

fn proofNumber(visitor_id: []const u8, bucket: u64) u32 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(proof_salt);
    hasher.update(visitor_id);
    hasher.update(std.mem.asBytes(&bucket));
    const digest = hasher.finalResult();
    return std.mem.readInt(u32, digest[0..4], .big);
}

// Passkey (WebAuthn level 2) ceremonies. Options go to the browser as JSON for
// `navigator.credentials.create/get` with binary fields base64url-encoded, and its
// answers come back the same way.
//
// Only "none" attestation is requested, so registration trusts whichever
// authenticator the signed-in user picks. User verification (PIN or biometric) is
// required both ways, since a passkey stands in for a whole sign-in.

pub const RelyingParty = struct {
    id: []const u8,
    name: []const u8,
    origin: []const u8,

    pub fn fromOrigin(name: []const u8, origin: []const u8) !RelyingParty {
        const uri = try std.Uri.parse(origin);
        const host = uri.host orelse return error.InvalidOrigin;
        return .{ .id = host.percent_encoded, .name = name, .origin = origin };
    }
};

// Base64url of 32 random bytes; the browser echoes it inside `clientDataJSON`.
pub const Challenge = [43]u8;

pub fn newChallenge(io: std.Io) Challenge {
    var bytes: [32]u8 = undefined;
    io.random(&bytes);
    var out: Challenge = undefined;
    _ = b64.Encoder.encode(&out, &bytes);
    return out;
}

// COSE ids. ES256 covers every platform authenticator, Ed25519 most security keys.
pub const Algorithm = enum(i64) { es256 = -7, ed25519 = -8 };

pub const User = struct {
    // Stable per account and free of personal data, so registering again replaces
    // the authenticator's old passkey instead of adding a second one.
    handle: []const u8,
    name: []const u8,
};

const timeout_ms = 5 * std.time.ms_per_min;

const Descriptor = struct { type: []const u8 = "public-key", id: []const u8 };

pub fn creationOptions(arena: std.mem.Allocator, rp: RelyingParty, user: User, challenge: []const u8, exclude: []const []const u8) ![]const u8 {
    const excluded = try arena.alloc(Descriptor, exclude.len);
    for (excluded, exclude) |*d, id| d.* = .{ .id = id };
    return std.json.Stringify.valueAlloc(arena, .{ .publicKey = .{
        .rp = .{ .id = rp.id, .name = rp.name },
        .user = .{ .id = try encode(arena, user.handle), .name = user.name, .displayName = user.name },
        .challenge = challenge,
        .pubKeyCredParams = [_]struct { type: []const u8 = "public-key", alg: i64 }{
            .{ .alg = @intFromEnum(Algorithm.es256) },
            .{ .alg = @intFromEnum(Algorithm.ed25519) },
        },
        .timeout = timeout_ms,
        .excludeCredentials = excluded,
        .authenticatorSelection = .{ .residentKey = "required", .requireResidentKey = true, .userVerification = "required" },
        .attestation = "none",
    } }, .{});
}

// No allow-list: the browser offers whichever passkeys it holds for the site.
pub fn requestOptions(arena: std.mem.Allocator, rp: RelyingParty, challenge: []const u8) ![]const u8 {
    return std.json.Stringify.valueAlloc(arena, .{ .publicKey = .{
        .rpId = rp.id,
        .challenge = challenge,
        .timeout = timeout_ms,
        .userVerification = "required",
        .allowCredentials = [_]Descriptor{},
    } }, .{});
}

// `public_key` is SEC1 uncompressed for ES256 and the raw 32 bytes for Ed25519.
pub const Credential = struct {
    id: []const u8,
    algorithm: Algorithm,
    public_key: []const u8,
    sign_count: u32,
};

pub fn verifyRegistration(arena: std.mem.Allocator, rp: RelyingParty, challenge: Challenge, body: []const u8) !Credential {
    const msg = std.json.parseFromSliceLeaky(struct {
        id: []const u8,
        response: struct { clientDataJSON: []const u8, attestationObject: []const u8 },
    }, arena, body, .{ .ignore_unknown_fields = true }) catch return error.InvalidResponse;

    try checkClientData(arena, rp, challenge, "webauthn.create", try decode(arena, msg.response.clientDataJSON));
    const data = try authenticatorData(rp, try attestedAuthData(try decode(arena, msg.response.attestationObject)));
    if (data.flags & flag_attested == 0) return error.InvalidResponse;

    // aaguid(16) | id length(2) | id | COSE key
    if (data.rest.len < 18) return error.InvalidResponse;
    const id_len = std.mem.readInt(u16, data.rest[16..18], .big);
    if (id_len > 1023 or data.rest.len < 18 + id_len) return error.InvalidResponse;
    const id = try encode(arena, data.rest[18..][0..id_len]);
    if (!std.mem.eql(u8, id, msg.id)) return error.InvalidResponse;

    var reader: Cbor = .{ .data = data.rest[18 + id_len ..] };
    const key = try coseKey(arena, &reader);
    return .{ .id = id, .algorithm = key.algorithm, .public_key = key.bytes, .sign_count = data.sign_count };
}

pub const Assertion = struct {
    credential_id: []const u8,
    client_data: []const u8,
    authenticator_data: []const u8,
    signature: []const u8,
};

pub fn parseAssertion(arena: std.mem.Allocator, body: []const u8) !Assertion {
    const msg = std.json.parseFromSliceLeaky(struct {
        id: []const u8,
        response: struct { clientDataJSON: []const u8, authenticatorData: []const u8, signature: []const u8 },
    }, arena, body, .{ .ignore_unknown_fields = true }) catch return error.InvalidResponse;
    return .{
        .credential_id = msg.id,
        .client_data = try decode(arena, msg.response.clientDataJSON),
        .authenticator_data = try decode(arena, msg.response.authenticatorData),
        .signature = try decode(arena, msg.response.signature),
    };
}

// Returns the counter to store. Synced passkeys always report 0; otherwise a
// counter that stops rising suggests a cloned authenticator.
pub fn verifyAssertion(arena: std.mem.Allocator, rp: RelyingParty, challenge: Challenge, assertion: Assertion, algorithm: Algorithm, public_key: []const u8, stored_count: u32) !u32 {
    try checkClientData(arena, rp, challenge, "webauthn.get", assertion.client_data);
    const data = try authenticatorData(rp, assertion.authenticator_data);

    var client_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(assertion.client_data, &client_hash, .{});
    try verifySignature(algorithm, public_key, assertion.signature, &.{ assertion.authenticator_data, &client_hash });

    if ((data.sign_count != 0 or stored_count != 0) and data.sign_count <= stored_count) return error.CounterRegressed;
    return data.sign_count;
}

fn checkClientData(arena: std.mem.Allocator, rp: RelyingParty, challenge: Challenge, kind: []const u8, raw: []const u8) !void {
    const client = std.json.parseFromSliceLeaky(struct {
        type: []const u8,
        challenge: []const u8,
        origin: []const u8,
        crossOrigin: bool = false,
    }, arena, raw, .{ .ignore_unknown_fields = true }) catch return error.InvalidResponse;
    if (!std.mem.eql(u8, client.type, kind)) return error.InvalidResponse;
    if (client.challenge.len != challenge.len or !std.crypto.timing_safe.eql(Challenge, client.challenge[0..challenge.len].*, challenge))
        return error.ChallengeMismatch;
    if (!std.mem.eql(u8, client.origin, rp.origin) or client.crossOrigin) return error.OriginMismatch;
}

const flag_user_present = 0x01;
const flag_user_verified = 0x04;
const flag_attested = 0x40;

const AuthenticatorData = struct { flags: u8, sign_count: u32, rest: []const u8 };

// rpIdHash(32) | flags(1) | signCount(4) | …
fn authenticatorData(rp: RelyingParty, data: []const u8) !AuthenticatorData {
    if (data.len < 37) return error.InvalidResponse;
    var rp_hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(rp.id, &rp_hash, .{});
    if (!std.mem.eql(u8, data[0..32], &rp_hash)) return error.RelyingPartyMismatch;
    const flags = data[32];
    if (flags & flag_user_present == 0 or flags & flag_user_verified == 0) return error.UserNotVerified;
    return .{ .flags = flags, .sign_count = std.mem.readInt(u32, data[33..37], .big), .rest = data[37..] };
}

// The attestation statement itself is ignored; only `authData` matters with "none".
fn attestedAuthData(object: []const u8) ![]const u8 {
    var r: Cbor = .{ .data = object };
    const pairs = try r.expect(.map);
    for (0..pairs) |_| {
        const key = try r.next();
        if (key == .text and std.mem.eql(u8, key.text, "authData")) return r.expect(.bytes);
        try r.skip();
    }
    return error.InvalidResponse;
}

const CoseKey = struct { algorithm: Algorithm, bytes: []const u8 };

fn coseKey(arena: std.mem.Allocator, r: *Cbor) !CoseKey {
    var kty: ?i64 = null;
    var alg: ?i64 = null;
    var crv: ?i64 = null;
    var x: ?[]const u8 = null;
    var y: ?[]const u8 = null;
    for (0..try r.expect(.map)) |_| switch (try r.expect(.int)) {
        1 => kty = try r.expect(.int),
        3 => alg = try r.expect(.int),
        -1 => crv = try r.expect(.int),
        -2 => x = try r.expect(.bytes),
        -3 => y = try r.expect(.bytes),
        else => try r.skip(),
    };

    const algorithm = std.enums.fromInt(Algorithm, alg orelse return error.InvalidResponse) orelse return error.UnsupportedAlgorithm;
    switch (algorithm) {
        .es256 => {
            if (kty != 2 or crv != 1) return error.UnsupportedAlgorithm;
            const px = x orelse return error.InvalidResponse;
            const py = y orelse return error.InvalidResponse;
            if (px.len != 32 or py.len != 32) return error.InvalidResponse;
            const sec1 = try std.mem.concat(arena, u8, &.{ &.{0x04}, px, py });
            _ = Es256.PublicKey.fromSec1(sec1) catch return error.InvalidResponse;
            return .{ .algorithm = algorithm, .bytes = sec1 };
        },
        .ed25519 => {
            if (kty != 1 or crv != 6) return error.UnsupportedAlgorithm;
            const px = x orelse return error.InvalidResponse;
            if (px.len != Ed25519.PublicKey.encoded_length) return error.InvalidResponse;
            _ = Ed25519.PublicKey.fromBytes(px[0..32].*) catch return error.InvalidResponse;
            return .{ .algorithm = algorithm, .bytes = px };
        },
    }
}

fn verifySignature(algorithm: Algorithm, public_key: []const u8, signature: []const u8, parts: []const []const u8) !void {
    switch (algorithm) {
        .es256 => {
            const pk = Es256.PublicKey.fromSec1(public_key) catch return error.BadSignature;
            const sig = Es256.Signature.fromDer(signature) catch return error.BadSignature;
            var v = sig.verifier(pk) catch return error.BadSignature;
            for (parts) |p| v.update(p);
            v.verify() catch return error.BadSignature;
        },
        .ed25519 => {
            if (public_key.len != Ed25519.PublicKey.encoded_length or signature.len != Ed25519.Signature.encoded_length) return error.BadSignature;
            const pk = Ed25519.PublicKey.fromBytes(public_key[0..32].*) catch return error.BadSignature;
            var v = Ed25519.Signature.fromBytes(signature[0..64].*).verifier(pk) catch return error.BadSignature;
            for (parts) |p| v.update(p);
            v.verify() catch return error.BadSignature;
        },
    }
}

const b64 = std.base64.url_safe_no_pad;

pub fn encode(arena: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const out = try arena.alloc(u8, b64.Encoder.calcSize(raw.len));
    return b64.Encoder.encode(out, raw);
}

pub fn decode(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const out = try arena.alloc(u8, b64.Decoder.calcSizeForSlice(text) catch return error.InvalidResponse);
    b64.Decoder.decode(out, text) catch return error.InvalidResponse;
    return out;
}

// What a browser and authenticator would send, built from a known key.
const Fake = struct {
    const rp: RelyingParty = .{ .id = "example.com", .name = "Test", .origin = "https://example.com" };
    const challenge: Challenge = "q83vEjRWeJCrze8SNFZ4kKvN7xI0VniQq83vEjRWeJA".*;
    const cred_id = [_]u8{ 0xaa, 0xbb, 0xcc, 0xdd };

    fn keyPair() !Es256.KeyPair {
        return Es256.KeyPair.generateDeterministic(@splat(7));
    }

    fn clientData(arena: std.mem.Allocator, kind: []const u8, origin: []const u8) ![]const u8 {
        return arena.print(
            \\{{"type":"{s}","challenge":"{s}","origin":"{s}","crossOrigin":false}}
        , .{ kind, &challenge, origin });
    }

    fn authData(arena: std.mem.Allocator, flags: u8, count: u32, attested: []const u8) ![]const u8 {
        var rp_hash: [32]u8 = undefined;
        Sha256.hash(rp.id, &rp_hash, .{});
        var tail: [5]u8 = undefined;
        tail[0] = flags;
        std.mem.writeInt(u32, tail[1..5], count, .big);
        return std.mem.concat(arena, u8, &.{ &rp_hash, &tail, attested });
    }

    fn registration(arena: std.mem.Allocator, origin: []const u8) ![]const u8 {
        const sec1 = (try keyPair()).public_key.toUncompressedSec1();
        // {1: 2, 3: -7, -1: 1, -2: x, -3: y}
        const cose = try std.mem.concat(arena, u8, &.{
            &.{ 0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20 }, sec1[1..33],
            &.{ 0x22, 0x58, 0x20 },                                            sec1[33..65],
        });
        const attested = try std.mem.concat(arena, u8, &.{ &@as([16]u8, @splat(0)), &.{ 0, cred_id.len }, &cred_id, cose });
        const auth_data = try authData(arena, flag_user_present | flag_user_verified | flag_attested, 0, attested);
        // {"fmt": "none", "attStmt": {}, "authData": h'…'}
        const object = try std.mem.concat(arena, u8, &.{
            &.{ 0xa3, 0x63 },                       "fmt",
            &.{0x64},                               "none",
            &.{0x67},                               "attStmt",
            &.{ 0xa0, 0x68 },                       "authData",
            &.{ 0x59, 0, @intCast(auth_data.len) }, auth_data,
        });
        return arena.print(
            \\{{"id":"{s}","response":{{"clientDataJSON":"{s}","attestationObject":"{s}"}}}}
        , .{ try encode(arena, &cred_id), try encode(arena, try clientData(arena, "webauthn.create", origin)), try encode(arena, object) });
    }

    fn assertion(arena: std.mem.Allocator, flags: u8, count: u32) !Assertion {
        const client = try clientData(arena, "webauthn.get", rp.origin);
        const auth_data = try authData(arena, flags, count, "");
        var client_hash: [32]u8 = undefined;
        Sha256.hash(client, &client_hash, .{});
        const sig = try (try keyPair()).sign(try std.mem.concat(arena, u8, &.{ auth_data, &client_hash }), null);
        var der: [Es256.Signature.der_encoded_length_max]u8 = undefined;
        return .{
            .credential_id = try encode(arena, &cred_id),
            .client_data = client,
            .authenticator_data = auth_data,
            .signature = try arena.dupe(u8, sig.toDer(&der)),
        };
    }
};

test "registration then sign-in" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const rp = Fake.rp;
    const challenge = Fake.challenge;

    const cred = try verifyRegistration(arena, rp, challenge, try Fake.registration(arena, rp.origin));
    try std.testing.expectEqualStrings("qrvM3Q", cred.id);
    try std.testing.expectEqual(Algorithm.es256, cred.algorithm);

    const uv = flag_user_present | flag_user_verified;
    try std.testing.expectEqual(5, try verifyAssertion(arena, rp, challenge, try Fake.assertion(arena, uv, 5), cred.algorithm, cred.public_key, 4));
    try std.testing.expectEqual(0, try verifyAssertion(arena, rp, challenge, try Fake.assertion(arena, uv, 0), cred.algorithm, cred.public_key, 0));
    try std.testing.expectError(error.CounterRegressed, verifyAssertion(arena, rp, challenge, try Fake.assertion(arena, uv, 5), cred.algorithm, cred.public_key, 5));
    try std.testing.expectError(error.UserNotVerified, verifyAssertion(arena, rp, challenge, try Fake.assertion(arena, flag_user_present, 0), cred.algorithm, cred.public_key, 0));
    try std.testing.expectError(error.ChallengeMismatch, verifyAssertion(arena, rp, @splat('A'), try Fake.assertion(arena, uv, 0), cred.algorithm, cred.public_key, 0));

    var tampered = try Fake.assertion(arena, uv, 0);
    tampered.authenticator_data = try Fake.authData(arena, uv, 9, "");
    try std.testing.expectError(error.BadSignature, verifyAssertion(arena, rp, challenge, tampered, cred.algorithm, cred.public_key, 0));

    const other: RelyingParty = .{ .id = rp.id, .name = rp.name, .origin = "https://evil.example" };
    try std.testing.expectError(error.OriginMismatch, verifyAssertion(arena, other, challenge, try Fake.assertion(arena, uv, 0), cred.algorithm, cred.public_key, 0));
}

test "registration from another origin is refused" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(error.OriginMismatch, verifyRegistration(arena, Fake.rp, Fake.challenge, try Fake.registration(arena, "https://evil.example")));
    try std.testing.expectError(error.InvalidResponse, verifyRegistration(arena, Fake.rp, Fake.challenge, "{}"));
}

test "RelyingParty.fromOrigin" {
    try std.testing.expectEqualStrings("example.com", (try RelyingParty.fromOrigin("", "https://example.com")).id);
    try std.testing.expectEqualStrings("localhost", (try RelyingParty.fromOrigin("", "http://localhost:3000")).id);
}

test requestOptions {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectEqualStrings(
        \\{"publicKey":{"rpId":"example.com","challenge":"c","timeout":300000,"userVerification":"required","allowCredentials":[]}}
    , try requestOptions(arena_state.allocator(), Fake.rp, "c"));
}

const std = @import("std");
const Cbor = @import("Cbor.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;
const Es256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;
const Ed25519 = std.crypto.sign.Ed25519;

const std = @import("std");
const types = @import("types.zig");

pub const ProtectedResource = struct {
    resource: []const u8,
    authorization_servers: []const []const u8,
    scopes_supported: []const []const u8 = &.{},
    bearer_methods_supported: []const []const u8 = &.{"header"},
    resource_documentation: ?[]const u8 = null,
};

pub const AuthorizationServer = struct {
    issuer: []const u8,
    authorization_endpoint: []const u8,
    token_endpoint: []const u8,
    registration_endpoint: ?[]const u8 = null,
    response_types_supported: []const []const u8 = &.{"code"},
    grant_types_supported: []const []const u8 = &.{ "authorization_code", "refresh_token" },
    code_challenge_methods_supported: []const []const u8 = &.{"S256"},
    token_endpoint_auth_methods_supported: []const []const u8 = &.{ "none", "client_secret_post" },
    scopes_supported: []const []const u8 = &.{},
};

pub const ClientRegistration = struct {
    client_id: []const u8,
    client_id_issued_at: i64,
    client_secret_expires_at: i64 = 0,
    client_name: ?[]const u8 = null,
    redirect_uris: []const []const u8,
    grant_types: []const []const u8 = &.{ "authorization_code", "refresh_token" },
    response_types: []const []const u8 = &.{"code"},
    token_endpoint_auth_method: []const u8 = "none",
    scope: ?[]const u8 = null,
};

pub const TokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8 = "Bearer",
    expires_in: u32,
    scope: ?[]const u8 = null,
};

pub const ErrorBody = struct {
    @"error": []const u8,
    error_description: ?[]const u8 = null,
};

pub fn writeProtectedResource(allocator: std.mem.Allocator, doc: ProtectedResource) ![]u8 {
    return types.stringify(allocator, doc);
}

pub fn writeAuthorizationServer(allocator: std.mem.Allocator, doc: AuthorizationServer) ![]u8 {
    return types.stringify(allocator, doc);
}

pub fn writeClientRegistration(allocator: std.mem.Allocator, doc: ClientRegistration) ![]u8 {
    return types.stringify(allocator, doc);
}

pub fn writeTokenResponse(allocator: std.mem.Allocator, access_token: []const u8, expires_in: u32, scope: ?[]const u8) ![]u8 {
    return types.stringify(allocator, TokenResponse{
        .access_token = access_token,
        .expires_in = expires_in,
        .scope = scope,
    });
}

pub fn writeOAuthError(allocator: std.mem.Allocator, err_code: []const u8, description: ?[]const u8) ![]u8 {
    return types.stringify(allocator, ErrorBody{
        .@"error" = err_code,
        .error_description = description,
    });
}

pub fn verifyPkceS256(verifier: []const u8, challenge: []const u8) bool {
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(verifier, &hash, .{});
    var enc_buf: [64]u8 = undefined;
    const enc = std.base64.url_safe_no_pad.Encoder.encode(&enc_buf, &hash);
    return std.mem.eql(u8, enc, challenge);
}

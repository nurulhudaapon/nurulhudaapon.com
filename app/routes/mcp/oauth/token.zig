const std = @import("std");
const zx = @import("zx");
const mcp = @import("mcp");
const store = @import("../store.zig");

pub fn handle(ctx: zx.RouteContext) !void {
    const fd = ctx.request.formData();
    const grant = fd.get("grant_type") orelse "";
    if (!std.mem.eql(u8, grant, "authorization_code")) {
        return oauthErr(ctx, .bad_request, "unsupported_grant_type", "Only authorization_code is supported");
    }

    const code = fd.get("code") orelse "";
    const redirect_uri = fd.get("redirect_uri") orelse "";
    const client_id = fd.get("client_id") orelse "";
    if (code.len == 0 or redirect_uri.len == 0 or client_id.len == 0) {
        return oauthErr(ctx, .bad_request, "invalid_request", "code, redirect_uri, and client_id are required");
    }

    const auth = (try store.consumeCode(ctx.arena, code)) orelse {
        return oauthErr(ctx, .bad_request, "invalid_grant", "Invalid or expired authorization code");
    };
    if (!std.mem.eql(u8, auth.client_id, client_id) or !std.mem.eql(u8, auth.redirect_uri, redirect_uri)) {
        return oauthErr(ctx, .bad_request, "invalid_grant", "client_id or redirect_uri mismatch");
    }

    const challenge = auth.code_challenge orelse {
        return oauthErr(ctx, .bad_request, "invalid_grant", "PKCE required");
    };
    const method = auth.code_challenge_method orelse "S256";
    if (!std.mem.eql(u8, method, "S256")) {
        return oauthErr(ctx, .bad_request, "invalid_request", "Only S256 PKCE is supported");
    }
    const verifier = fd.get("code_verifier") orelse {
        return oauthErr(ctx, .bad_request, "invalid_request", "code_verifier required");
    };
    if (!mcp.oauth.verifyPkceS256(verifier, challenge)) {
        return oauthErr(ctx, .bad_request, "invalid_grant", "PKCE verification failed");
    }

    const issued = try store.issueAccessToken(ctx.arena, auth.client_id, auth.scope, auth.resource, auth.approved_by);
    const body = try mcp.oauth.writeTokenResponse(ctx.arena, issued.token, issued.expires_in, auth.scope);
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(body);
}

fn oauthErr(ctx: zx.RouteContext, status: std.http.Status, code: []const u8, desc: []const u8) !void {
    const body = try mcp.oauth.writeOAuthError(ctx.arena, code, desc);
    ctx.response.setStatus(status);
    ctx.response.headers.append("Cache-Control", "no-store");
    ctx.response.setContentType(.@"application/json");
    ctx.response.text(body);
}

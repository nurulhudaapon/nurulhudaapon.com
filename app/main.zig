const std = @import("std");
const zx = @import("zx");
const migration = @import("db/migration.zig");
const env = @import("env.zig");
const credentials = @import("db/credentials.zig");
const github = @import("github.zig");

pub fn main(init: zx.Init) !void {
    // The browser build gets std.process.Init.Minimal, which has no io.
    const io = if (@hasField(zx.Init, "io")) init.io else {};
    var app = try zx.App.init(init, io, zx.allocator, .{}, {});
    defer app.deinit();

    try migration.run();
    env.load(init);
    if (comptime zx.platform.role == .server) githubToken();

    try app.start();
}

fn githubToken() void {
    var arena: std.heap.ArenaAllocator = .init(zx.allocator);
    defer arena.deinit();
    const token = credentials.fromSecret(arena.allocator(), "github_token") orelse return;
    github.setToken(token) catch |err| zx.log.warn("github token: {any}", .{err});
}

pub const std_options = zx.std_options;

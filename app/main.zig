const std = @import("std");
const zx = @import("zx");
const migration = @import("db/migration.zig");
const env = @import("env.zig");

pub fn main(init: zx.Init) !void {
    // The browser build gets std.process.Init.Minimal, which has no io.
    const io = if (@hasField(zx.Init, "io")) init.io else {};
    var app = try zx.App.init(init, io, zx.allocator, .{}, {});
    defer app.deinit();

    try migration.run();
    env.load(init);

    try app.start();
}

pub const std_options = zx.std_options;

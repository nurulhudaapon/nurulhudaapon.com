const zx = @import("zx");
const migration = @import("db/migration.zig");
const env = @import("db/env.zig");

pub fn main(init: zx.Init) !void {
    var app = try zx.App.init(init, zx.io(), zx.allocator, .{}, {});
    defer app.deinit();

    try migration.run();
    env.load(init);

    try app.start();
}

pub const std_options = zx.std_options;

const std = @import("std");
const zx = @import("zx");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zx_site_mod", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zx_site",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zx_site_mod", .module = mod },
            },
        }),
    });

    const zx_build = try zx.init(b, exe, .{});
    var client = zx_build.client.?;
    client.root_module.addImport("zx_site_mod", mod);
}

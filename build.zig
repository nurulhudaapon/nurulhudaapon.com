const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Ziex App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "ziex_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const markz_dep = b.dependency("markz", .{ .target = target, .optimize = optimize });
    app_exe.root_module.addImport("markz", markz_dep.module("markz"));

    // --- Ziex setup: wires dependencies and adds `zx`/`dev` build steps ---
    var ziex_b = try ziex.init(b, app_exe, .{
        .cli = .{ .optimize = optimize },
        .app = .{
            .features = .{
                .kv = .enabled,
            },
        },
    });
    ziex_b = ziex_b; // ignore unused
}

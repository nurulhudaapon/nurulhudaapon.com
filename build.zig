const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_labs = b.option(bool, "labs", "Show Nuhu Labs links and CTAs") orelse false;

    // --- ziex App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "nuhu_dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const config = b.addOptions();
    config.addOption(bool, "labs", enable_labs);
    app_exe.root_module.addOptions("config", config);

    app_exe.root_module.addImport("lunasvg", b.dependency("lunasvg", .{
        .target = target,
        .optimize = optimize,
    }).module("lunasvg"));

    // --- ziex setup: wires dependencies and adds `ziex`/`dev` build steps ---
    _ = try ziex.init(b, app_exe, .{
        .cli = .{ .optimize = optimize },
        .app = .{
            .server = .{ .backend = .std },
            .client = .{
                .bindings = .{
                    .build = .enabled,
                    .install_subdir = "bindings",
                },
            },
        },
    });
}

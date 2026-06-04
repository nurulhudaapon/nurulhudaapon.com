const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zx_site_mod", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // --- Ziex App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "ziex_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    app_exe.root_module.addImport("zx_site_mod", mod);

    // --- Ziex setup: wires dependencies and adds `zx`/`dev` build steps ---
    var ziex_b = try ziex.init(b, app_exe, .{});
    ziex_b = ziex_b; // ignore unused
}

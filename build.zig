const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Ziex App Executable ---
    const app_exe = b.addExecutable(.{
        .name = "nurulhudaapon_com",
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
                .sqlite = .enabled,
            },
            .client = .{
                .bindings = .{
                    .link = false,
                    .build = .enabled,
                    .install_subdir = "bindings",
                },
                .wasm = .disabled,
            },
        },
    });

    ziex_b.addImport("lunasvg", b.dependency("lunasvg", .{
        .target = target,
        .optimize = optimize,
    }).module("lunasvg"));

    ziex_b.addImport("geist_fonts", addGeistFontsModule(b));
}

fn addGeistFontsModule(b: *std.Build) *std.Build.Module {
    const geist = b.dependency("geist_font", .{});
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(geist.path("Geist/ttf/Geist-Regular.ttf"), "Geist-Regular.ttf");
    _ = wf.addCopyFile(geist.path("Geist/ttf/Geist-Bold.ttf"), "Geist-Bold.ttf");
    const root = wf.add("root.zig",
        \\pub const regular = @embedFile("Geist-Regular.ttf");
        \\pub const bold = @embedFile("Geist-Bold.ttf");
        \\
    );
    return b.createModule(.{
        .root_source_file = root,
    });
}

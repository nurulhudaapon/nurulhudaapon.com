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

    installGeistFonts(b, app_exe);

    // --- Ziex setup: wires dependencies and adds `zx`/`dev` build steps ---
    var ziex_b = try ziex.init(b, app_exe, .{
        .cli = .{ .optimize = optimize, .zig_path = "zig" },
        .app = .{
            .features = .{
                .kv = .enabled,
                .sqlite = .enabled,
            },
            .client = .{
                .bindings = .{
                    .from_source = true,
                    .install_subdir = "bindings",
                },
            },
        },
    });
    ziex_b = ziex_b; // ignore unused
}

fn installGeistFonts(b: *std.Build, app_exe: *std.Build.Step.Compile) void {
    const geist = b.dependency("geist_font", .{});

    const fonts = [_]struct { src: []const u8, dest: []const u8 }{
        .{
            .src = "fonts/Geist/webfonts/Geist[wght].woff2",
            .dest = "static/fonts/geist-sans.woff2",
        },
        .{
            .src = "fonts/GeistMono/webfonts/GeistMono[wght].woff2",
            .dest = "static/fonts/geist-mono.woff2",
        },
    };

    for (fonts) |font| {
        const install = b.addInstallFile(geist.path(font.src), font.dest);
        install.step.name = b.fmt("install {s}", .{font.dest});
        b.getInstallStep().dependOn(&install.step);
        app_exe.step.dependOn(&install.step);
    }
}

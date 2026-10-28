const std = @import("std");
const ziex = @import("ziex");
const libical = @import("lib/ical/build.zig");

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
                .cache = .enabled,
            },
            .server = .{
                .backend = .std,
            },
            .client = .{
                .bindings = .{
                    .build = .enabled,
                    .install_subdir = "bindings",
                },
            },
        },
    });

    ziex_b.addImport("lunasvg", b.dependency("lunasvg", .{
        .target = target,
        .optimize = optimize,
    }).module("lunasvg"));

    ziex_b.addImport("geist_fonts", addGeistFontsModule(b));
    ziex_b.addImport("highlight", b.dependency("highlight", .{ .target = target, .optimize = optimize }).module("highlight"));
    ziex_b.addImport("mcp", b.dependency("mcp", .{ .target = target, .optimize = optimize }).module("mcp"));
    const auth_mod = b.dependency("auth", .{ .target = target, .optimize = optimize }).module("auth");
    ziex_b.addImport("auth", auth_mod);
    ziex_b.addImport("xml", b.dependency("xml", .{ .target = target, .optimize = optimize }).module("xml"));

    const ical_mod = libical.addLibical(b, target, optimize);
    ziex_b.addImport("ical", ical_mod);

    // --- Post editor preview: markdown + tree-sitter as its own wasm, loaded only by that page ---
    const wasi = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const preview = b.addExecutable(.{
        .name = "preview",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/preview.zig"),
            .target = wasi,
            .optimize = .ReleaseSmall,
            .link_libc = true,
            .imports = &.{
                .{ .name = "markz", .module = b.dependency("markz", .{ .target = wasi, .optimize = .ReleaseSmall }).module("markz") },
                .{ .name = "highlight", .module = b.dependency("highlight", .{ .target = wasi, .optimize = .ReleaseSmall }).module("highlight") },
            },
        }),
    });
    preview.entry = .disabled;
    preview.wasi_exec_model = .reactor;
    preview.root_module.export_symbol_names = &.{
        "preview_reset",     "preview_alloc",     "preview_render",   "preview_minutes",
        "preview_title_ptr", "preview_title_len", "preview_html_ptr", "preview_html_len",
    };
    b.getInstallStep().dependOn(&b.addInstallFile(preview.getEmittedBin(), "static/assets/_/preview.wasm").step);

    // --- Unit tests ---
    const test_step = b.step("test", "Run unit tests");
    for ([_][]const u8{ "app/pages/schedule/slots.zig", "app/pages/schedule/ical.zig", "app/pages/schedule/caldav.zig", "app/pages/schedule/name.zig", "app/pages/finance/number.zig" }) |path| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "ical", .module = ical_mod }},
        }) });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = auth_mod })).step);
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

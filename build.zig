const std = @import("std");
const ziex = @import("ziex");
const libical = @import("app/lib/ical/build_ical.zig");
const highlight = @import("app/lib/highlight/build_highlight.zig");

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

    // Pure Zig: the same module serves the server, client and worker.
    ziex_b.addImport("markz", b.dependency("markz", .{ .target = target, .optimize = optimize }).module("markz"));
    const xml_mod = b.dependency("xml", .{ .target = target, .optimize = optimize }).module("xml");
    ziex_b.addImport("xml", xml_mod);

    const ical_mod = libical.addLibical(b, target, optimize);
    for (ziex_b.platforms) |p| {
        if (p.kind == .server) {
            p.addImport("lunasvg", b.dependency("lunasvg", .{ .target = p.target, .optimize = p.optimize }).module("lunasvg"));
            p.addImport("geist_fonts", addGeistFontsModule(b));
            p.addImport("ical", ical_mod);
        }
        // The server renders posts; the post editor's preview worker
        // (`pages/admin/posts/[slug]/worker.zig`) renders them in the browser.
        if (p.kind != .client) {
            const highlight_mod = highlight.addHighlight(b, p.target, p.optimize);
            p.linkLibc(highlight_mod);
            p.addImport("highlight", highlight_mod);
        }
    }

    // --- Unit tests ---
    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("app/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ical", .module = ical_mod },
            .{ .name = "xml", .module = xml_mod },
        },
    }) });
    test_step.dependOn(&b.addRunArtifact(tests).step);
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

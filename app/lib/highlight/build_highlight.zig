const std = @import("std");

/// tree-sitter highlighting for the languages the blog uses. Called from the root
/// `build.zig`, so ziex and the grammars come from the root `build.zig.zon`.
pub fn addHighlight(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const ziex = b.dependency("ziex", .{});
    const tree_sitter = ziex.builder.dependency("tree_sitter", .{ .target = target, .optimize = optimize });

    const Grammar = struct { name: []const u8, root: std.Build.LazyPath, src: []const u8 = "src", scanner: bool = false };
    const grammars = [_]Grammar{
        .{ .name = "zx", .root = ziex.path("pkg/tree-sitter-zx") },
        .{ .name = "javascript", .root = b.dependency("tree_sitter_javascript", .{}).path(""), .scanner = true },
        .{ .name = "typescript", .root = b.dependency("tree_sitter_typescript", .{}).path(""), .src = "typescript/src", .scanner = true },
        .{ .name = "zig", .root = b.dependency("tree_sitter_zig", .{}).path("") },
        .{ .name = "bash", .root = b.dependency("tree_sitter_bash", .{}).path(""), .scanner = true },
        .{ .name = "json", .root = b.dependency("tree_sitter_json", .{}).path("") },
    };

    // The grammars are their own library so they compile against the target's libc
    // headers even when linked into a freestanding wasm (a `zx.worker`).
    const c = b.addLibrary(.{
        .name = "highlight-grammars",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });

    const wf = b.addWriteFiles();
    const mod = b.createModule(.{
        .root_source_file = wf.addCopyFile(b.path("app/lib/highlight/root.zig"), "root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "tree_sitter", .module = tree_sitter.module("tree_sitter") }},
    });
    mod.linkLibrary(c);
    for (grammars) |g| {
        const src = g.root.path(b, g.src);
        c.root_module.addCSourceFile(.{ .file = src.path(b, "parser.c"), .flags = &.{"-std=c11"} });
        if (g.scanner) {
            c.root_module.addIncludePath(src);
            c.root_module.addCSourceFile(.{ .file = src.path(b, "scanner.c"), .flags = &.{"-std=c11"} });
        }
        _ = wf.addCopyFile(g.root.path(b, "queries/highlights.scm"), b.fmt("{s}.scm", .{g.name}));
    }
    return mod;
}

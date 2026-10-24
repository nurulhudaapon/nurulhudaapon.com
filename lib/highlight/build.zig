const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const wf = b.addWriteFiles();
    const mod = b.addModule("highlight", .{
        .root_source_file = wf.addCopyFile(b.path("root.zig"), "root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "tree_sitter", .module = tree_sitter.module("tree_sitter") }},
    });
    for (grammars) |g| {
        const src = g.root.path(b, g.src);
        mod.addCSourceFile(.{ .file = src.path(b, "parser.c"), .flags = &.{"-std=c11"} });
        if (g.scanner) {
            mod.addIncludePath(src);
            mod.addCSourceFile(.{ .file = src.path(b, "scanner.c"), .flags = &.{"-std=c11"} });
        }
        _ = wf.addCopyFile(g.root.path(b, "queries/highlights.scm"), b.fmt("{s}.scm", .{g.name}));
    }
}

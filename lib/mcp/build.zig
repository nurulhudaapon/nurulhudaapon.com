const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addMcpModule(b, target, optimize);
}

pub fn addMcpModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const spec = b.dependency("mcp_spec", .{});
    const schema = spec.path("schema/2025-11-25/schema.json");

    const gen_exe = b.addExecutable(.{
        .name = "mcp-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const gen_dir = b.addWriteFiles();
    inline for (.{ "version", "methods", "error_codes", "defs_index" }) |kind| {
        const run = b.addRunArtifact(gen_exe);
        run.addArg(kind);
        run.addFileArg(schema);
        _ = gen_dir.addCopyFile(run.captureStdOut(.{}), b.fmt("{s}.zig", .{kind}));
    }

    _ = gen_dir.addCopyFile(b.path("root.zig"), "root.zig");
    _ = gen_dir.addCopyFile(b.path("jsonrpc.zig"), "jsonrpc.zig");
    _ = gen_dir.addCopyFile(b.path("types.zig"), "types.zig");
    _ = gen_dir.addCopyFile(b.path("server.zig"), "server.zig");
    _ = gen_dir.addCopyFile(b.path("http.zig"), "http.zig");
    _ = gen_dir.addCopyFile(b.path("oauth.zig"), "oauth.zig");

    return b.addModule("mcp", .{
        .root_source_file = gen_dir.getDirectory().path(b, "root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

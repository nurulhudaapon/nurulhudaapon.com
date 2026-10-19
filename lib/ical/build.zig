const std = @import("std");

const version = .{ .major = 3, .minor = 0, .patch = 20 };

const sources = [_][]const u8{
    "icalarray.c",    "icalattach.c",   "icalcomponent.c", "icalenums.c",
    "icalerror.c",    "icalmemory.c",   "icalmime.c",      "icalparameter.c",
    "icalparser.c",   "icalproperty.c", "icalrecur.c",     "icaltime.c",
    "icaltz-util.c",  "icaltimezone.c", "icalduration.c",  "icalperiod.c",
    "icaltypes.c",    "icalvalue.c",    "pvl.c",           "sspm.c",
    "icallangbind.c", "caldate.c",
};

// Order matters: it is upstream's ical_file.cmake order for the combined ical.h.
const public_headers = [_][]const u8{
    "icalversion.h",   "icaltime.h",            "icalduration.h",         "icalperiod.h",
    "icalenums.h",     "icaltypes.h",           "icalarray.h",            "icalrecur.h",
    "icalattach.h",    "icalderivedvalue.h",    "icalderivedparameter.h", "icalvalue.h",
    "icalparameter.h", "icalderivedproperty.h", "icalproperty.h",         "pvl.h",
    "icalcomponent.h", "icaltimezone.h",        "icaltz-util.h",          "icalparser.h",
    "icalmemory.h",    "icalerror.h",           "icalrestriction.h",      "sspm.h",
    "icalmime.h",      "icallangbind.h",
};

const ical_h = blk: {
    var s: []const u8 = "";
    for (public_headers) |h| s = s ++ "#include \"" ++ h ++ "\"\n";
    break :blk s;
};

const Generated = struct {
    out: []const u8,
    kind: []const u8,
    csvs: []const []const u8,
};

const generated = [_]Generated{
    .{ .out = "icalderivedvalue.h", .kind = "values-h", .csvs = &.{"value-types.csv"} },
    .{ .out = "icalderivedvalue.c", .kind = "values-c", .csvs = &.{"value-types.csv"} },
    .{ .out = "icalderivedparameter.h", .kind = "parameters-h", .csvs = &.{"parameters.csv"} },
    .{ .out = "icalderivedparameter.c", .kind = "parameters-c", .csvs = &.{"parameters.csv"} },
    .{ .out = "icalderivedproperty.h", .kind = "properties-h", .csvs = &.{ "properties.csv", "value-types.csv" } },
    .{ .out = "icalderivedproperty.c", .kind = "properties-c", .csvs = &.{ "properties.csv", "value-types.csv" } },
    .{ .out = "icalrestriction.c", .kind = "restrictions", .csvs = &.{"restrictions.csv"} },
};

const generated_sources = blk: {
    var out: []const []const u8 = &.{};
    for (generated) |g| {
        if (std.mem.endsWith(u8, g.out, ".c")) out = out ++ .{g.out};
    }
    break :blk out;
};

const flags = [_][]const u8{
    "-std=gnu99",
    "-DHAVE_CONFIG_H",
    "-Dlibical_ical_EXPORTS",
    "-DPACKAGE_DATA_DIR=\"\"",
    "-fno-sanitize=undefined",
    "-Wno-everything",
};

pub fn addLibical(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const upstream = b.dependency("libical", .{});
    const src_dir = upstream.path("src/libical");

    const gen_exe = b.addExecutable(.{
        .name = "libical-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/ical/gen.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const gen_dir = b.addWriteFiles();
    for (generated) |g| {
        const run = b.addRunArtifact(gen_exe);
        run.addArg(g.kind);
        run.addFileArg(src_dir.path(b, b.fmt("{s}.in", .{g.out})));
        for (g.csvs) |csv| run.addFileArg(upstream.path(b.fmt("design-data/{s}", .{csv})));
        _ = gen_dir.addCopyFile(run.captureStdOut(.{}), g.out);
    }
    const header = gen_dir.add("ical.h", ical_h);

    const version_h = b.addConfigHeader(.{
        .style = .{ .cmake = src_dir.path(b, "icalversion.h.cmake") },
        .include_path = "icalversion.h",
    }, .{
        .CMAKE_PROJECT_NAME = "libical",
        .PROJECT_VERSION = b.fmt("{d}.{d}", .{ version.major, version.minor }),
        .LIBICAL_LIB_MAJOR_VERSION = version.major,
        .LIBICAL_LIB_MINOR_VERSION = version.minor,
        .LIBICAL_LIB_PATCH_VERSION = version.patch,
    });

    const lib_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    lib_mod.addIncludePath(b.path("lib/ical"));
    lib_mod.addIncludePath(gen_dir.getDirectory());
    lib_mod.addConfigHeader(version_h);
    lib_mod.addIncludePath(src_dir);
    lib_mod.addCSourceFiles(.{ .root = src_dir, .files = &sources, .flags = &flags });
    lib_mod.addCSourceFiles(.{ .root = gen_dir.getDirectory(), .files = generated_sources, .flags = &flags });
    if (target.result.os.tag == .wasi) {
        lib_mod.addCMacro("_WASI_EMULATED_SIGNAL", "1");
        lib_mod.addCMacro("_WASI_EMULATED_PROCESS_CLOCKS", "1");
    }
    const lib = b.addLibrary(.{ .name = "ical", .linkage = .static, .root_module = lib_mod });

    const translate = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize });
    translate.addIncludePath(gen_dir.getDirectory());
    translate.addConfigHeader(version_h);
    translate.addIncludePath(src_dir);

    const mod = translate.createModule();
    mod.linkLibrary(lib);
    return mod;
}

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) return error.Usage;

    const kind = args[1];
    const schema_path = args[2];
    const cwd = std.Io.Dir.cwd();
    const raw = try cwd.readFileAlloc(io, schema_path, arena, .unlimited);

    const parsed = try std.json.parseFromSlice(std.json.Value, arena, raw, .{ .allocate = .alloc_always });
    const root = parsed.value;
    if (root != .object) return error.InvalidSchema;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    if (std.mem.eql(u8, kind, "version")) {
        try emitVersion(w);
    } else if (std.mem.eql(u8, kind, "methods")) {
        try emitMethods(arena, w, root.object);
    } else if (std.mem.eql(u8, kind, "error_codes")) {
        try emitErrorCodes(w);
    } else if (std.mem.eql(u8, kind, "defs_index")) {
        try emitDefsIndex(arena, w, root.object);
    } else return error.Usage;

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    try stdout.interface.writeAll(out.written());
    try stdout.interface.flush();
}

fn emitVersion(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\pub const protocol_version = "2025-11-25";
        \\
    );
}

fn emitErrorCodes(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\pub const parse_error: i64 = -32700;
        \\pub const invalid_request: i64 = -32600;
        \\pub const method_not_found: i64 = -32601;
        \\pub const invalid_params: i64 = -32602;
        \\pub const internal_error: i64 = -32603;
        \\
    );
}

const MethodEntry = struct {
    wire: []const u8,
    tag: []const u8,
    def_name: []const u8,
};

fn emitMethods(arena: std.mem.Allocator, w: *std.Io.Writer, root: std.json.ObjectMap) !void {
    const defs_val = root.get("$defs") orelse return error.MissingDefs;
    if (defs_val != .object) return error.InvalidDefs;

    var list: std.ArrayListUnmanaged(MethodEntry) = .empty;
    var it = defs_val.object.iterator();
    while (it.next()) |entry| {
        const def_name = entry.key_ptr.*;
        const is_req = std.mem.endsWith(u8, def_name, "Request");
        const is_notif = std.mem.endsWith(u8, def_name, "Notification");
        if (!is_req and !is_notif) continue;
        const method = findMethodConst(entry.value_ptr.*) orelse continue;
        const tag = try wireToTag(arena, method);
        try list.append(arena, .{ .wire = method, .tag = tag, .def_name = def_name });
    }

    std.mem.sort(MethodEntry, list.items, {}, struct {
        fn less(_: void, a: MethodEntry, b: MethodEntry) bool {
            return std.mem.order(u8, a.wire, b.wire) == .lt;
        }
    }.less);

    try w.writeAll(
        \\pub const Method = enum {
        \\
    );
    for (list.items) |m| {
        try w.print("    {s},\n", .{m.tag});
    }
    try w.writeAll(
        \\
        \\    pub fn toString(self: Method) []const u8 {
        \\        return switch (self) {
        \\
    );
    for (list.items) |m| {
        try w.print("            .{s} => \"{s}\",\n", .{ m.tag, m.wire });
    }
    try w.writeAll(
        \\        };
        \\    }
        \\
        \\    pub fn fromString(s: []const u8) ?Method {
        \\        inline for (@typeInfo(Method).@"enum".field_names, @typeInfo(Method).@"enum".field_values) |_, value| {
        \\            const m: Method = @enumFromInt(value);
        \\            if (std.mem.eql(u8, m.toString(), s)) return m;
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
        \\const std = @import("std");
        \\
        \\pub fn defName(method: Method) []const u8 {
        \\    return switch (method) {
        \\
    );
    for (list.items) |m| {
        try w.print("        .{s} => \"{s}\",\n", .{ m.tag, m.def_name });
    }
    try w.writeAll(
        \\    };
        \\}
        \\
    );
}

fn emitDefsIndex(arena: std.mem.Allocator, w: *std.Io.Writer, root: std.json.ObjectMap) !void {
    const defs_val = root.get("$defs") orelse return error.MissingDefs;
    if (defs_val != .object) return error.InvalidDefs;

    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    var it = defs_val.object.iterator();
    while (it.next()) |entry| try names.append(arena, entry.key_ptr.*);
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);

    try w.writeAll(
        \\pub const defs = [_][]const u8{
        \\
    );
    for (names.items) |n| {
        try w.print("    \"{s}\",\n", .{n});
    }
    try w.writeAll("};\n");
}

fn findMethodConst(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;
    if (value.object.get("properties")) |props| {
        if (props == .object) {
            if (props.object.get("method")) |m| {
                if (m == .object) {
                    if (m.object.get("const")) |c| {
                        if (c == .string) return c.string;
                    }
                }
            }
        }
    }
    if (value.object.get("allOf")) |all_of| {
        if (all_of == .array) {
            for (all_of.array.items) |part| {
                if (findMethodConst(part)) |m| return m;
            }
        }
    }
    return null;
}

fn wireToTag(arena: std.mem.Allocator, wire: []const u8) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (wire) |c| {
        if (c == '/' or c == '-') {
            try out.append(arena, '_');
        } else {
            try out.append(arena, c);
        }
    }
    return out.items;
}

// Zig port of libical's Perl generators. Output must stay byte-identical to theirs.

const std = @import("std");

const Kind = enum { @"values-h", @"values-c", @"parameters-h", @"parameters-c", @"properties-h", @"properties-c", restrictions };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) return error.Usage;

    const kind = std.meta.stringToEnum(Kind, args[1]) orelse return error.Usage;
    const cwd = std.Io.Dir.cwd();
    const template = try cwd.readFileAlloc(io, args[2], arena, .unlimited);
    var csvs: [2][]const u8 = .{ "", "" };
    for (args[3..], 0..) |path, i| csvs[i] = try cwd.readFileAlloc(io, path, arena, .unlimited);

    var out: std.Io.Writer.Allocating = .init(arena);
    var g: Gen = .{ .a = arena, .w = &out.writer };
    switch (kind) {
        .@"values-h", .@"values-c" => try g.values(template, csvs[0], kind == .@"values-h"),
        .@"parameters-h", .@"parameters-c" => try g.parameters(template, csvs[0], kind == .@"parameters-h"),
        .@"properties-h", .@"properties-c" => try g.properties(template, csvs[0], csvs[1], kind == .@"properties-h"),
        .restrictions => try g.restrictions(template, csvs[0]),
    }

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    try stdout.interface.writeAll(out.written());
    try stdout.interface.flush();
}

const Value = struct {
    autogen: bool,
    c_type: []const u8,
    kind: []const u8,
    components: []const []const u8,
    enums: []const []const u8,
};

const Property = struct {
    lic_value: []const u8,
    kind: []const u8,
    default_value: []const u8,
    flags: []const []const u8,
};

const Parameter = struct {
    c_type: []const u8,
    kind: []const u8,
    enums: []const []const u8,
};

const Gen = struct {
    a: std.mem.Allocator,
    w: *std.Io.Writer,

    fn values(g: *Gen, template: []const u8, csv: []const u8, header: bool) !void {
        const h = try readValues(g.a, csv);
        var lines = TemplateLines{ .text = template };
        while (lines.next()) |line| {
            if (contains(line, "<insert_code_here>")) try g.valuesInsert(h, header) else try g.w.writeAll(line);
        }
        if (header) try g.w.writeAll("#endif /*ICALVALUE_H*/\n");
    }

    fn valuesInsert(g: *Gen, h: std.StringArrayHashMapUnmanaged(Value), header: bool) !void {
        const w = g.w;
        const keys = try sortedKeys(g.a, h);

        if (header) {
            try w.print("typedef enum icalvalue_kind {{\n   ICAL_ANY_VALUE={s},\n", .{kindOf(Value, h, "ANY")});
            for (keys) |value| {
                if (!truthy(value) or eql(value, "NO") or eql(value, "ANY")) continue;
                try w.print("    ICAL_{s}_VALUE={s},\n", .{ try upperNoDash(g.a, value), h.get(value).?.kind });
            }
            try w.print("   ICAL_NO_VALUE={s}\n}} icalvalue_kind ;\n\n", .{kindOf(Value, h, "NO")});

            var idx: i64 = 10000;
            var lastidx: i64 = 10000;
            try w.print("#define ICALPROPERTY_FIRST_ENUM {d}\n\n", .{idx});
            for (keys) |value| {
                if (!truthy(value) or eql(value, "NO") or eql(value, "ANY")) continue;
                const v = h.get(value).?;
                if (v.enums.len == 0) continue;
                const ucv = try upperNoDash(g.a, value);
                try w.print("typedef {s} {{\n", .{v.c_type});
                for (v.enums, 0..) |e, i| {
                    if (i != 0) try w.writeAll(",\n");
                    const pe = parseEnum(e);
                    idx = if (pe.num) |n| try parseNum(n) else idx + 1;
                    lastidx = @max(lastidx, idx);
                    try w.print("    ICAL_{s}_{s} = {d}", .{ ucv, try upperNoDash(g.a, pe.name), idx });
                }
                try w.print("\n}} {s};\n\n", .{try replaceFirst(g.a, v.c_type, "enum ", "")});
            }
            try w.print("#define ICALPROPERTY_LAST_ENUM {d}\n", .{lastidx + 1});
        } else {
            try w.print("static const struct icalvalue_kind_map value_map[{d}]={{\n", .{h.count() + 1});
            for (keys) |value| {
                if (eql(value, "NO") or eql(value, "ANY")) continue;
                try w.print("    {{ICAL_{s}_VALUE,\"{s}\"}},\n", .{ try upperNoDash(g.a, value), value });
            }
            try w.writeAll("    {ICAL_NO_VALUE,\"\"}\n};");
        }

        for (keys) |value| {
            if (eql(value, "ANY")) continue;
            const v = h.get(value).?;
            const t = try replaceFirst(g.a, v.c_type, "char*", "char *");
            const lc = try lowerNoDash(g.a, value);
            const uc = try upperNoDash(g.a, value);
            const is_ptr = contains(t, "*");
            const pointer_check: []const u8 = if (is_ptr) "    icalerror_check_arg_rz((v != 0), \"v\");\n" else "";
            const pointer_check_rv: []const u8 = if (is_ptr) "    icalerror_check_arg_rv((v != 0), \"v\");\n" else "";
            const assign: []const u8 = if (contains(t, "char"))
                "icalmemory_strdup(v);\n\n    if (impl->data.v_string == 0) {\n        errno = ENOMEM;\n    }\n"
            else
                "v;";
            const union_data: []const u8 = if (v.enums.len > 0) "enum" else unionMap(uc) orelse lc;

            if (!header and v.autogen) {
                try w.print(
                    "\nicalvalue *icalvalue_new_{s}({s} v)\n{{\n    struct icalvalue_impl *impl;\n{s}\n" ++
                        "    impl = icalvalue_new_impl(ICAL_{s}_VALUE);\n    icalvalue_set_{s}((icalvalue *)impl, v);\n" ++
                        "    return (icalvalue*)impl;\n}}\n\nvoid icalvalue_set_{s}(icalvalue *value, {s} v)\n{{\n" ++
                        "    struct icalvalue_impl *impl;\n    icalerror_check_arg_rv((value != 0), \"value\");\n{s}\n" ++
                        "    icalerror_check_value_type(value, ICAL_{s}_VALUE);\n    impl = (struct icalvalue_impl *)value;\n",
                    .{ lc, t, pointer_check, uc, lc, lc, t, pointer_check_rv, uc },
                );
                if (eql(union_data, "string")) {
                    try w.print("    if (impl->data.v_{s} != 0) {{\n        free((void *)impl->data.v_{s});\n    }}\n", .{ union_data, union_data });
                }
                try w.print("\n    impl->data.v_{s} = {s}\n    icalvalue_reset_kind(impl);\n}}\n\n", .{ union_data, assign });
                try w.print("{s} icalvalue_get_{s}(const icalvalue *value)\n{{\n", .{ t, lc });
                if (eql(union_data, "string")) {
                    try w.writeAll("    icalerror_check_arg_rz((value != 0), \"value\");\n");
                } else {
                    try w.writeAll("    icalerror_check_arg((value != 0), \"value\");\n");
                    if (eql(union_data, "enum")) {
                        try w.print("    if (!value) {{\n        return ICAL_{s}_NONE;\n    }}\n", .{uc});
                    } else if (nullReturn(union_data)) |ret| {
                        try w.writeAll(ret);
                    }
                }
                try w.print("    icalerror_check_value_type(value, ICAL_{s}_VALUE);\n    return ((struct icalvalue_impl *)value)->data.v_{s};\n}}\n", .{ uc, union_data });
            } else if (header and v.autogen) {
                try w.print(
                    "\n/* {s} */\nLIBICAL_ICAL_EXPORT icalvalue *icalvalue_new_{s}({s} v);\n" ++
                        "LIBICAL_ICAL_EXPORT {s} icalvalue_get_{s}(const icalvalue *value);\n" ++
                        "LIBICAL_ICAL_EXPORT void icalvalue_set_{s}(icalvalue *value, {s} v);\n",
                    .{ value, lc, t, t, lc, lc, t },
                );
            }
        }
    }

    fn parameters(g: *Gen, template: []const u8, csv: []const u8, header: bool) !void {
        const params = try readParameters(g.a, csv);
        const msg = "of section of machine generated code (mkderivedparameters.pl). Do not edit.";
        var lines = TemplateLines{ .text = template };
        while (lines.next()) |line| {
            if (contains(line, "<insert_code_here>")) {
                try g.w.writeAll("/* START " ++ msg ++ " */\n\n");
                try g.parametersInsert(params, header);
                try g.w.writeAll("/* END   " ++ msg ++ " */\n\n");
            } else try g.w.writeAll(line);
        }
    }

    fn parametersInsert(g: *Gen, params: std.StringArrayHashMapUnmanaged(Parameter), header: bool) !void {
        const w = g.w;
        const keys = try sortedKeys(g.a, params);

        if (header) {
            try w.print("typedef enum icalparameter_kind {{\n    ICAL_ANY_PARAMETER = {s},\n", .{kindOf(Parameter, params, "ANY")});
            for (keys) |param| {
                if (!truthy(param) or eql(param, "NO") or eql(param, "ANY")) continue;
                try w.print("    ICAL_{s}_PARAMETER = {s},\n", .{ try upperNoDash(g.a, param), params.get(param).?.kind });
            }
            try w.print("    ICAL_NO_PARAMETER = {s}\n}} icalparameter_kind;\n\n", .{kindOf(Parameter, params, "NO")});

            var idx: i64 = 20000;
            var lastidx: i64 = 20000;
            try w.print("#define ICALPARAMETER_FIRST_ENUM {d}\n\n", .{idx});
            for (keys) |param| {
                if (!truthy(param) or eql(param, "NO") or eql(param, "ANY")) continue;
                const p = params.get(param).?;
                if (p.enums.len == 0) continue;
                const ucv = try upperNoDash(g.a, param);
                try w.print("typedef enum {s} {{\n", .{p.c_type});
                for (p.enums, 0..) |e, i| {
                    if (i != 0) try w.writeAll(",\n");
                    const pe = parseEnum(e);
                    idx = if (pe.num) |n| try parseNum(n) else idx + 1;
                    lastidx = @max(lastidx, idx);
                    try w.print("    ICAL_{s}_{s} = {d}", .{ ucv, try upperNoDash(g.a, pe.name), idx });
                }
                try w.print("\n}} {s};\n\n", .{p.c_type});
            }
            try w.print("#define ICALPARAMETER_LAST_ENUM {d}\n\n", .{lastidx + 1});
        } else {
            var out: std.Io.Writer.Allocating = .init(g.a);
            var count: usize = 0;
            if (params.get("VALUE")) |value_param| for (value_param.enums) |e| {
                const name = parseEnum(e).name;
                if (eql(name, "X") or eql(name, "NONE") or eql(name, "NO") or eql(name, "ERROR")) continue;
                const uc = try upperNoDash(g.a, name);
                try out.writer.print("    {{ICAL_VALUE_{s}, ICAL_{s}_VALUE}},\n", .{ uc, uc });
                count += 1;
            };
            try w.print("static const struct icalparameter_value_kind_map value_kind_map[{d}] = {{\n{s}", .{ count + 2, out.written() });
            try w.writeAll("    {ICAL_VALUE_X, ICAL_X_VALUE},\n    {ICAL_VALUE_NONE, ICAL_NO_VALUE}\n};\n\n");

            out.clearRetainingCapacity();
            count = 0;
            for (keys) |param| {
                if (!truthy(param) or eql(param, "NO") or eql(param, "ANY")) continue;
                count += 1;
                try out.writer.print("    {{ICAL_{s}_PARAMETER, \"{s}\"}},\n", .{ try upperNoDash(g.a, param), param });
            }
            try w.print("static const struct icalparameter_kind_map parameter_map[{d}] = {{\n{s}", .{ count + 1, out.written() });
            try w.writeAll("    { ICAL_NO_PARAMETER, \"\"}\n};\n\n");

            out.clearRetainingCapacity();
            for (keys) |param| {
                if (!truthy(param) or eql(param, "NO") or eql(param, "ANY")) continue;
                const uc = try upperNoDash(g.a, param);
                for (params.get(param).?.enums) |e| {
                    const name = parseEnum(e).name;
                    if (eql(name, "X") or eql(name, "NONE")) continue;
                    try out.writer.print("    {{ICAL_{s}_PARAMETER,ICAL_{s}_{s}, \"{s}\"}},\n", .{ uc, uc, try upperNoDash(g.a, name), name });
                }
            }
            try w.print("static const struct icalparameter_map icalparameter_map[] = {{\n    {{ICAL_ANY_PARAMETER, 0, \"\"}},\n{s}", .{out.written()});
            try w.writeAll("    {ICAL_NO_PARAMETER, 0, \"\"}\n};\n\n");
        }

        for (keys) |param| {
            if (eql(param, "NO") or eql(param, "ANY")) continue;
            var t = params.get(param).?.c_type;
            const lc = try lowerNoDash(g.a, param);
            const uc = try upperNoDash(g.a, param);

            var charorenum: []const u8 = undefined;
            var set_code: []const u8 = undefined;
            var pointer_check: []const u8 = "";
            var pointer_check_v: []const u8 = "";
            if (contains(t, "char")) {
                t = try replaceFirst(g.a, t, "char*", "char *");
                charorenum = "    icalerror_check_arg_rz((param != 0), \"param\");\n    return param->string;";
                set_code = "((struct icalparameter_impl *)param)->string = icalmemory_strdup(v);";
                pointer_check = "    icalerror_check_arg_rz((v != 0), \"v\");";
                pointer_check_v = "\n    icalerror_check_arg_rv((v != 0), \"v\");";
            } else if (contains(t, "int")) {
                charorenum = "    icalerror_check_arg((param != 0), \"param\");\n" ++
                    "    if (param != 0) {\n       return param->data;\n    } else {\n       return 0;\n    }";
                set_code = "((struct icalparameter_impl *)param)->data = v;";
            } else {
                const no_xname = for ([_][]const u8{ "RELATED", "RANGE", "RSVP", "XLICERRORTYPE", "XLICCOMPARETYPE" }) |n| {
                    if (eql(n, uc)) break true;
                } else false;
                const xrange = if (no_xname) "" else try std.fmt.allocPrint(g.a, "    if (param->string != 0) {{\n        return ICAL_{s}_X;\n    }}\n", .{uc});
                charorenum = try std.fmt.allocPrint(g.a, "    icalerror_check_arg((param != 0), \"param\");\n    if (!param) {{\n        return ICAL_{s}_NONE;\n    }}\n{s}\n    return ({s})(param->data);", .{ uc, xrange, t });
                pointer_check = try std.fmt.allocPrint(g.a, "    icalerror_check_arg_rz(v >= ICAL_{s}_X, \"v\");\n    icalerror_check_arg_rz(v < ICAL_{s}_NONE, \"v\");", .{ uc, uc });
                pointer_check_v = try std.fmt.allocPrint(g.a, "\n    icalerror_check_arg_rv(v >= ICAL_{s}_X, \"v\");\n    icalerror_check_arg_rv(v < ICAL_{s}_NONE, \"v\");", .{ uc, uc });
                set_code = "((struct icalparameter_impl *)param)->data = (int)v;";
            }

            if (!header) {
                try w.print(
                    \\/* {s} */
                    \\icalparameter *icalparameter_new_{s}({s} v)
                    \\{{
                    \\    struct icalparameter_impl *impl;
                    \\    icalerror_clear_errno();
                    \\{s}
                    \\    impl = icalparameter_new_impl(ICAL_{s}_PARAMETER);
                    \\    if (impl == 0) {{
                    \\       return 0;
                    \\    }}
                    \\
                    \\    icalparameter_set_{s}((icalparameter *)impl, v);
                    \\    if (icalerrno != ICAL_NO_ERROR) {{
                    \\       icalparameter_free((icalparameter *)impl);
                    \\       return 0;
                    \\    }}
                    \\
                    \\    return (icalparameter *)impl;
                    \\}}
                    \\
                    \\{s} icalparameter_get_{s}(const icalparameter *param)
                    \\{{
                    \\    icalerror_clear_errno();
                    \\{s}
                    \\}}
                    \\
                    \\void icalparameter_set_{s}(icalparameter *param, {s} v)
                    \\{{{s}
                    \\    icalerror_check_arg_rv((param != 0), "param");
                    \\    icalerror_clear_errno();
                    \\
                    \\    if (param->string != NULL) {{
                    \\        free((void *)param->string);
                    \\    }}
                    \\    {s}
                    \\}}
                    \\
                    \\
                , .{ param, lc, t, pointer_check, uc, lc, t, lc, charorenum, lc, t, pointer_check_v, set_code });
            } else {
                try w.print(
                    \\/* {s} */
                    \\LIBICAL_ICAL_EXPORT icalparameter * icalparameter_new_{s}({s} v);
                    \\LIBICAL_ICAL_EXPORT {s} icalparameter_get_{s}(const icalparameter *value);
                    \\LIBICAL_ICAL_EXPORT void icalparameter_set_{s}(icalparameter *value, {s} v);
                    \\
                    \\
                , .{ param, lc, t, t, lc, lc, t });
            }
        }

        if (header) try w.writeAll("#endif /*ICALPARAMETER_H*/\n\n");
    }

    fn properties(g: *Gen, template: []const u8, props_csv: []const u8, values_csv: []const u8, header: bool) !void {
        const props = try readProperties(g.a, props_csv);
        const vals = try readValues(g.a, values_csv);
        var lines = TemplateLines{ .text = template };
        while (lines.next()) |line| {
            if (contains(line, "<insert_code_here>")) try g.propertiesInsert(props, vals, header) else try g.w.writeAll(line);
        }
    }

    const Fudged = struct { uc: []const u8, lc: []const u8, lcvalue: []const u8, ucvalue: []const u8, t: []const u8, comp_types: []const []const u8 };

    fn fudge(g: *Gen, props: std.StringArrayHashMapUnmanaged(Property), vals: std.StringArrayHashMapUnmanaged(Value), prop: []const u8) !Fudged {
        const value = if (props.get(prop)) |p| p.lic_value else "";
        if (!truthy(value)) return error.MissingPropertyValue;
        const v = vals.get(value);
        return .{
            .uc = try upperNoDash(g.a, prop),
            .lc = try lowerNoDash(g.a, prop),
            .lcvalue = try lowerNoDash(g.a, value),
            .ucvalue = try upperNoDash(g.a, value),
            .t = try replaceFirst(g.a, if (v) |x| x.c_type else "", "char*", "char *"),
            .comp_types = if (v) |x| x.components else &.{},
        };
    }

    fn propertiesInsert(g: *Gen, props: std.StringArrayHashMapUnmanaged(Property), vals: std.StringArrayHashMapUnmanaged(Value), header: bool) !void {
        const w = g.w;
        const keys = try sortedKeys(g.a, props);

        if (!header) {
            const by_kind = try g.a.dupe([]const u8, keys);
            std.sort.block([]const u8, by_kind, props, struct {
                fn lt(p: std.StringArrayHashMapUnmanaged(Property), x: []const u8, y: []const u8) bool {
                    return perlNum(p.get(x).?.kind) < perlNum(p.get(y).?.kind);
                }
            }.lt);

            try w.print("static const struct icalproperty_map property_map[{d}] = {{\n", .{by_kind.len});
            for (by_kind) |prop| {
                if (!truthy(prop) or eql(prop, "NO") or eql(prop, "ANY")) continue;
                const f = try g.fudge(props, vals, prop);
                const p = props.get(prop).?;
                const defvalue = try removeAll(g.a, p.default_value, '-');
                try w.print("    {{ ICAL_{s}_PROPERTY, \"{s}\",\n      ICAL_{s}_VALUE, ICAL_{s}_VALUE,\n      {{ ", .{ f.uc, prop, f.ucvalue, defvalue });
                if (f.comp_types.len > 0) {
                    for (f.comp_types) |comp| try w.print("ICAL_{s}_VALUE, ", .{try removeAll(g.a, comp, '-')});
                } else if (!eql(defvalue, "NO")) {
                    try w.print("ICAL_{s}_VALUE, ", .{defvalue});
                } else {
                    try w.print("ICAL_{s}_VALUE, ", .{f.ucvalue});
                }
                try w.writeAll("ICAL_NO_VALUE }, ");
                if (p.flags.len > 0) {
                    var sep: []const u8 = "\n      ";
                    for (p.flags) |flag| {
                        try w.print("{s}ICAL_PROPERTY_{s}", .{ sep, try std.ascii.allocUpperString(g.a, try removeAll(g.a, flag, '-')) });
                        sep = " | ";
                    }
                } else try w.writeAll("0");
                try w.writeAll(" },\n");
            }
            const no = try g.fudge(props, vals, "NO");
            try w.print("    {{ ICAL_{s}_PROPERTY, \"\",      ICAL_NO_VALUE, ICAL_NO_VALUE,\n      {{ ICAL_NO_VALUE }}, 0 }}\n}};\n\n", .{no.uc});

            // Perl sorts these numeric keys as strings.
            var lines: std.AutoArrayHashMapUnmanaged(i64, []const u8) = .empty;
            var bigcount: usize = 0;
            var idx: i64 = 0;
            var saveidx: i64 = 0;
            const value_keys = try sortedKeys(g.a, vals);
            for (value_keys) |value| {
                // The script's ANY check tests `$prop` (always "NO" here), so ANY is not skipped.
                if (!truthy(value) or eql(value, "NO")) continue;
                const v = vals.get(value).?;
                const ucv = try upperNoDash(g.a, value);
                for (v.enums) |e| {
                    const pe = parseEnum(e);
                    idx = if (pe.num) |n| try parseNum(n) else idx + 1;
                    const uce = try upperNoDash(g.a, pe.name);
                    const str = if (!eql(pe.name, "X") and !eql(pe.name, "NONE")) pe.name else "";
                    if (eql(pe.name, "NONE")) {
                        bigcount += 100;
                        saveidx += 1;
                        while (saveidx < idx) : (saveidx += 1) {
                            try lines.put(g.a, saveidx, try std.fmt.allocPrint(g.a, "    {{ICAL_{s}_PROPERTY,ICAL_{s}_NONE, \"\" }}, /*{d}*/\n", .{ ucv, ucv, saveidx }));
                        }
                    }
                    try lines.put(g.a, idx, try std.fmt.allocPrint(g.a, "    {{ICAL_{s}_PROPERTY,ICAL_{s}_{s}, \"{s}\" }}, /*{d}*/\n", .{ ucv, ucv, uce, str, idx }));
                    saveidx = idx;
                }
            }
            try w.print("static const struct icalproperty_enum_map enum_map[{d}] = {{\n", .{bigcount + 1});
            const line_keys = try g.a.alloc([]const u8, lines.count());
            for (lines.keys(), 0..) |k, i| line_keys[i] = try std.fmt.allocPrint(g.a, "{d}", .{k});
            std.sort.block([]const u8, line_keys, {}, lessThanStr);
            for (line_keys) |k| try w.writeAll(lines.get(try std.fmt.parseInt(i64, k, 10)).?);
            try w.writeAll("    {ICAL_NO_PROPERTY, 0, \"\"}\n};\n\n");
        } else {
            try w.print("typedef enum icalproperty_kind {{\n    ICAL_ANY_PROPERTY = {s},\n", .{kindOf(Property, props, "ANY")});
            for (keys) |prop| {
                if (!truthy(prop) or eql(prop, "NO") or eql(prop, "ANY")) continue;
                const f = try g.fudge(props, vals, prop);
                try w.print("    ICAL_{s}_PROPERTY = {s},\n", .{ f.uc, props.get(prop).?.kind });
            }
            try w.print("    ICAL_NO_PROPERTY = {s}\n}} icalproperty_kind;\n", .{kindOf(Property, props, "NO")});
        }

        for (keys) |prop| {
            if (!truthy(prop) or eql(prop, "NO") or eql(prop, "ANY")) continue;
            const f = try g.fudge(props, vals, prop);
            const is_ptr = contains(f.t, "*");
            const pointer_check: []const u8 = if (is_ptr) "    icalerror_check_arg_rz((v != 0), \"v\");\n" else "";
            const set_pointer_check: []const u8 = if (is_ptr) "\n    icalerror_check_arg_rv((v != 0), \"v\");" else "";

            if (!header) {
                try w.print(
                    \\icalproperty *icalproperty_vanew_{s}({s} v, ...)
                    \\{{
                    \\    va_list args;
                    \\    struct icalproperty_impl *impl;
                    \\{s}
                    \\    impl = icalproperty_new_impl(ICAL_{s}_PROPERTY);
                    \\    icalproperty_set_{s}((icalproperty*)impl, v);
                    \\    va_start(args, v);
                    \\    icalproperty_add_parameters(impl, args);
                    \\    va_end(args);
                    \\    return (icalproperty*)impl;
                    \\}}
                    \\
                    \\/* {s} */
                    \\icalproperty *icalproperty_new_{s}({s} v)
                    \\{{
                    \\    struct icalproperty_impl *impl;
                    \\{s}
                    \\    impl = icalproperty_new_impl(ICAL_{s}_PROPERTY);
                    \\    icalproperty_set_{s}((icalproperty*)impl, v);
                    \\    return (icalproperty*)impl;
                    \\}}
                    \\
                    \\void icalproperty_set_{s}(icalproperty *prop, {s} v)
                    \\{{{s}
                    \\    icalerror_check_arg_rv((prop != 0), "prop");
                    \\    icalproperty_set_value(prop, icalvalue_new_{s}(v));
                    \\}}
                    \\
                    \\
                , .{ f.lc, f.t, pointer_check, f.uc, f.lc, prop, f.lc, f.t, pointer_check, f.uc, f.lc, f.lc, f.t, set_pointer_check, f.lcvalue });
                if (eql(f.lc, "exdate")) {
                    try w.print(
                        \\{s} icalproperty_get_{s}(const icalproperty *prop)
                        \\{{
                        \\    icalerror_check_arg((prop != 0), "prop");
                        \\    return icalproperty_get_datetime_with_component((icalproperty *)prop, NULL);
                        \\}}
                        \\
                        \\
                    , .{ f.t, f.lc });
                } else {
                    try w.print(
                        \\{s} icalproperty_get_{s}(const icalproperty *prop)
                        \\{{
                        \\    icalerror_check_arg((prop != 0), "prop");
                        \\    return icalvalue_get_{s}(icalproperty_get_value(prop));
                        \\}}
                        \\
                        \\
                    , .{ f.t, f.lc, f.lcvalue });
                }
            } else {
                try w.print(
                    "\n/* {s} */\nLIBICAL_ICAL_EXPORT icalproperty *icalproperty_new_{s}({s} v);\n" ++
                        "LIBICAL_ICAL_EXPORT void icalproperty_set_{s}(icalproperty *prop, {s} v);\n" ++
                        "LIBICAL_ICAL_EXPORT {s} icalproperty_get_{s}(const icalproperty *prop);" ++
                        "\nLIBICAL_ICAL_EXPORT icalproperty *icalproperty_vanew_{s}({s} v, ...);\n",
                    .{ prop, f.lc, f.t, f.lc, f.t, f.t, f.lc, f.lc, f.t },
                );
            }
        }

        if (header) try w.writeAll("\n#endif /*ICALPROPERTY_H*/\n");
    }

    fn restrictions(g: *Gen, template: []const u8, csv: []const u8) !void {
        var lines = TemplateLines{ .text = template };
        while (lines.next()) |line| {
            // The script's CSV loop clobbers `$_`, so the marker line itself is never printed.
            if (contains(line, "<insert_code_here>")) {
                try g.restrictionsInsert(csv);
                continue;
            }
            if (contains(line, "Do not edit")) break;
            try g.w.writeAll(line);
        }
    }

    fn restrictionsInsert(g: *Gen, csv: []const u8) !void {
        const w = g.w;
        try w.writeAll("static const icalrestriction_property_record icalrestriction_property_records[] = {\n");
        var rows = CsvLines{ .text = csv };
        while (rows.next()) |raw| {
            const line = stripComment(raw);
            const col = try perlSplit(g.a, line, ',');
            const method = field(col, 0);
            if (!truthy(method)) continue;
            const sub = field(col, 5);
            const sub_fn = if (truthy(sub)) try std.fmt.allocPrint(g.a, "icalrestriction_{s}", .{sub}) else "NULL";
            const restr = std.mem.trimEnd(u8, field(col, 4), " \t\r\n\x0c");
            if (!eql(field(col, 2), "NONE")) {
                try w.print("    {{ICAL_METHOD_{s}, ICAL_{s}_COMPONENT, ICAL_{s}_PROPERTY, ICAL_RESTRICTION_{s}, {s}}},\n", .{ method, field(col, 1), field(col, 2), restr, sub_fn });
            }
        }
        try w.writeAll("    {ICAL_METHOD_NONE, ICAL_NO_COMPONENT, ICAL_NO_PROPERTY, ICAL_RESTRICTION_NONE, NULL}\n};\n");
    }
};

fn dataRows(a: std.mem.Allocator, csv: []const u8) ![]const []const []const u8 {
    var out: std.ArrayList([]const []const u8) = .empty;
    var rows = CsvLines{ .text = csv };
    while (rows.next()) |raw| {
        const no_comment = stripComment(raw);
        var clean: std.ArrayList(u8) = .empty;
        for (no_comment) |ch| if (ch != '"' and ch != '\r') try clean.append(a, ch);
        if (!truthy(clean.items)) continue;
        try out.append(a, try perlSplit(a, clean.items, ','));
    }
    return out.items;
}

fn readValues(a: std.mem.Allocator, csv: []const u8) !std.StringArrayHashMapUnmanaged(Value) {
    var h: std.StringArrayHashMapUnmanaged(Value) = .empty;
    for (try dataRows(a, csv)) |col| {
        const c_type_str = field(col, 2);
        const components = field(col, 4);
        const enum_values = field(col, 5);
        try h.put(a, field(col, 0), .{
            .autogen = contains(c_type_str, "(a)"),
            .c_type = try removeFirstParenChar(a, c_type_str),
            .kind = field(col, 1),
            .components = if (eql(components, "unitary")) &.{} else try perlSplit(a, components, ';'),
            .enums = if (truthy(enum_values)) try perlSplit(a, enum_values, ';') else &.{},
        });
    }
    return h;
}

fn readProperties(a: std.mem.Allocator, csv: []const u8) !std.StringArrayHashMapUnmanaged(Property) {
    var h: std.StringArrayHashMapUnmanaged(Property) = .empty;
    for (try dataRows(a, csv)) |col| {
        const flags = field(col, 4);
        try h.put(a, field(col, 0), .{
            .lic_value = field(col, 2),
            .kind = field(col, 1),
            .default_value = field(col, 3),
            .flags = if (flags.len > 0) try perlSplit(a, flags, ';') else &.{},
        });
    }
    return h;
}

fn readParameters(a: std.mem.Allocator, csv: []const u8) !std.StringArrayHashMapUnmanaged(Parameter) {
    var h: std.StringArrayHashMapUnmanaged(Parameter) = .empty;
    for (try dataRows(a, csv)) |col| {
        const enum_string = field(col, 3);
        try h.put(a, field(col, 0), .{
            .c_type = field(col, 2),
            .kind = field(col, 1),
            .enums = if (truthy(enum_string)) try perlSplit(a, enum_string, ';') else &.{},
        });
    }
    return h;
}

const TemplateLines = struct {
    text: []const u8,
    pos: usize = 0,

    fn next(self: *TemplateLines) ?[]const u8 {
        if (self.pos >= self.text.len) return null;
        const end = if (std.mem.indexOfScalarPos(u8, self.text, self.pos, '\n')) |nl| nl + 1 else self.text.len;
        defer self.pos = end;
        return self.text[self.pos..end];
    }
};

// Perl's `chop` drops the last char even when it is not a newline.
const CsvLines = struct {
    text: []const u8,
    pos: usize = 0,

    fn next(self: *CsvLines) ?[]const u8 {
        if (self.pos >= self.text.len) return null;
        const end = if (std.mem.indexOfScalarPos(u8, self.text, self.pos, '\n')) |nl| nl + 1 else self.text.len;
        defer self.pos = end;
        return self.text[self.pos .. end - 1];
    }
};

fn stripComment(line: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, line, '#')) |i| line[0..i] else line;
}

fn perlSplit(a: std.mem.Allocator, s: []const u8, sep: u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, s, sep);
    while (it.next()) |p| try parts.append(a, p);
    while (parts.items.len > 0 and parts.items[parts.items.len - 1].len == 0) _ = parts.pop();
    return parts.items;
}

fn field(cols: []const []const u8, i: usize) []const u8 {
    return if (i < cols.len) cols[i] else "";
}

fn truthy(s: []const u8) bool {
    return s.len > 0 and !eql(s, "0");
}

fn perlNum(s: []const u8) i64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) end += 1;
    return std.fmt.parseInt(i64, s[0..end], 10) catch 0;
}

fn parseNum(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 10);
}

// `/([a-zA-Z0-9\-]+)=?([0-9]+)?/`, where a "0" capture counts as absent.
fn parseEnum(e: []const u8) struct { name: []const u8, num: ?[]const u8 } {
    const isName = struct {
        fn f(ch: u8) bool {
            return std.ascii.isAlphanumeric(ch) or ch == '-';
        }
    }.f;
    var start: usize = 0;
    while (start < e.len and !isName(e[start])) start += 1;
    var end = start;
    while (end < e.len and isName(e[end])) end += 1;
    var i = end;
    if (i < e.len and e[i] == '=') i += 1;
    const digits_start = i;
    while (i < e.len and std.ascii.isDigit(e[i])) i += 1;
    const num = e[digits_start..i];
    return .{ .name = e[start..end], .num = if (truthy(num)) num else null };
}

fn upperNoDash(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    return std.ascii.allocUpperString(a, try removeAll(a, s, '-'));
}

fn lowerNoDash(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    return std.ascii.allocLowerString(a, try removeAll(a, s, '-'));
}

fn removeAll(a: std.mem.Allocator, s: []const u8, ch: u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| if (c != ch) try out.append(a, c);
    return out.items;
}

fn replaceFirst(a: std.mem.Allocator, s: []const u8, needle: []const u8, repl: []const u8) ![]const u8 {
    const i = std.mem.indexOf(u8, s, needle) orelse return s;
    return std.mem.concat(a, u8, &.{ s[0..i], repl, s[i + needle.len ..] });
}

fn removeFirstParenChar(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var i: usize = 0;
    while (i + 2 < s.len) : (i += 1) {
        if (s[i] == '(' and s[i + 1] != '\n' and s[i + 2] == ')') return std.mem.concat(a, u8, &.{ s[0..i], s[i + 3 ..] });
    }
    return s;
}

fn unionMap(uc: []const u8) ?[]const u8 {
    const map = std.StaticStringMap([]const u8).initComptime(.{
        .{ "BOOLEAN", "int" },       .{ "CALADDRESS", "string" }, .{ "DATE", "time" },
        .{ "DATETIME", "time" },     .{ "DATETIMEDATE", "time" }, .{ "DATETIMEPERIOD", "period" },
        .{ "DURATION", "duration" }, .{ "INTEGER", "int" },       .{ "TEXT", "string" },
        .{ "URI", "string" },        .{ "UTCOFFSET", "int" },     .{ "QUERY", "string" },
        .{ "X", "string" },
    });
    return map.get(uc);
}

fn nullReturn(union_data: []const u8) ?[]const u8 {
    const map = std.StaticStringMap([]const u8).initComptime(.{
        .{ "int", "    if (!value) {\n        return 0;\n    }\n" },
        .{ "float", "    if (!value) {\n        return 0.0;\n     }\n" },
        .{ "time", "    if (!value) {\n        return icaltime_null_time();\n    }\n" },
        .{ "duration", "    if (!value) {\n        return icaldurationtype_null_duration();\n    }\n" },
        .{ "period", "    if (!value) {\n        return icalperiodtype_null_period();\n    }\n" },
        .{ "requeststatus", "    if (!value) {\n        return icalreqstattype_from_string(\"0.0\");\n    }\n" },
    });
    return map.get(union_data);
}

fn kindOf(comptime T: type, h: std.StringArrayHashMapUnmanaged(T), key: []const u8) []const u8 {
    return if (h.get(key)) |v| v.kind else "";
}

fn sortedKeys(a: std.mem.Allocator, h: anytype) ![]const []const u8 {
    const keys = try a.dupe([]const u8, h.keys());
    std.sort.block([]const u8, keys, {}, lessThanStr);
    return keys;
}

fn lessThanStr(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.lessThan(u8, x, y);
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn eql(x: []const u8, y: []const u8) bool {
    return std.mem.eql(u8, x, y);
}

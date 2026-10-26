const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");
const methods = @import("methods.zig");
const version = @import("version.zig");
const types = @import("types.zig");

pub const ToolHandler = *const fn (allocator: std.mem.Allocator, args: ?std.json.Value) anyerror!types.ToolResult;

pub const RegisteredTool = struct {
    tool: types.Tool,
    handler: ToolHandler,
};

pub const Config = struct {
    name: []const u8,
    version: []const u8 = "1.0.0",
    title: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    config: Config,
    tools: std.ArrayListUnmanaged(RegisteredTool) = .empty,

    pub fn init(allocator: std.mem.Allocator, config: Config) Server {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn deinit(self: *Server) void {
        self.tools.deinit(self.allocator);
    }

    pub fn addTool(self: *Server, tool: types.Tool, handler: ToolHandler) !void {
        try self.tools.append(self.allocator, .{ .tool = tool, .handler = handler });
    }

    pub fn handleMessage(self: *Server, allocator: std.mem.Allocator, body: []const u8) ![]u8 {
        const msg = jsonrpc.parse(allocator, body) catch {
            return jsonrpc.writeErrorParse(allocator, "Parse error");
        };
        if (msg.is_response) {
            return jsonrpc.writeError(allocator, msg.id orelse .null, jsonrpc.codes.invalid_request, "Server does not accept responses");
        }

        const method = methods.Method.fromString(msg.method) orelse {
            if (msg.is_notification) return try allocator.dupe(u8, "");
            return jsonrpc.writeError(allocator, msg.id orelse .null, jsonrpc.codes.method_not_found, "Method not found");
        };

        if (msg.is_notification) return try allocator.dupe(u8, "");

        const id = msg.id orelse .null;
        return switch (method) {
            .initialize => try self.handleInitialize(allocator, id),
            .ping => try jsonrpc.writeResult(allocator, id, .{}),
            .tools_list => try self.handleToolsList(allocator, id),
            .tools_call => try self.handleToolsCall(allocator, id, msg.params),
            else => jsonrpc.writeError(allocator, id, jsonrpc.codes.method_not_found, "Method not implemented"),
        };
    }

    fn handleInitialize(self: *Server, allocator: std.mem.Allocator, id: jsonrpc.Id) ![]u8 {
        return jsonrpc.writeResult(allocator, id, types.InitializeResult{
            .protocolVersion = version.protocol_version,
            .capabilities = .{ .tools = .{ .listChanged = false } },
            .serverInfo = .{
                .name = self.config.name,
                .version = self.config.version,
                .title = self.config.title,
            },
            .instructions = self.config.instructions,
        });
    }

    fn handleToolsList(self: *Server, allocator: std.mem.Allocator, id: jsonrpc.Id) ![]u8 {
        const descriptors = try allocator.alloc(types.ToolDescriptor, self.tools.items.len);
        for (self.tools.items, descriptors) |reg, *d| {
            d.* = .{
                .name = reg.tool.name,
                .description = reg.tool.description,
                .inputSchema = .{ .bytes = reg.tool.input_schema_json },
                .annotations = reg.tool.annotations,
            };
        }
        return jsonrpc.writeResult(allocator, id, types.ToolsListResult{ .tools = descriptors });
    }

    fn handleToolsCall(self: *Server, allocator: std.mem.Allocator, id: jsonrpc.Id, params: ?std.json.Value) ![]u8 {
        const p = params orelse {
            return jsonrpc.writeError(allocator, id, jsonrpc.codes.invalid_params, "Missing params");
        };
        if (p != .object) {
            return jsonrpc.writeError(allocator, id, jsonrpc.codes.invalid_params, "params must be object");
        }
        const name_v = p.object.get("name") orelse {
            return jsonrpc.writeError(allocator, id, jsonrpc.codes.invalid_params, "Missing tool name");
        };
        if (name_v != .string) {
            return jsonrpc.writeError(allocator, id, jsonrpc.codes.invalid_params, "Tool name must be string");
        }

        const reg = for (self.tools.items) |t| {
            if (std.mem.eql(u8, t.tool.name, name_v.string)) break t;
        } else {
            return jsonrpc.writeError(allocator, id, jsonrpc.codes.invalid_params, "Unknown tool");
        };

        const result = reg.handler(allocator, p.object.get("arguments")) catch |err| {
            const msg = try std.fmt.allocPrint(allocator, "Tool error: {s}", .{@errorName(err)});
            return writeToolResult(allocator, id, try types.ToolResult.err(allocator, msg));
        };
        return writeToolResult(allocator, id, result);
    }
};

fn writeToolResult(allocator: std.mem.Allocator, id: jsonrpc.Id, result: types.ToolResult) ![]u8 {
    return jsonrpc.writeResult(allocator, id, types.CallToolResult{
        .content = result.content,
        .isError = result.isError,
        .structuredContent = result.structuredContent,
    });
}

pub const Tool = types.Tool;
pub const ToolResult = types.ToolResult;
pub const ToolAnnotations = types.ToolAnnotations;

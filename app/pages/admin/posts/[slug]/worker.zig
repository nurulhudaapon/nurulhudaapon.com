// The post editor's preview renderer, run through `zx.worker` so markdown and
// tree-sitter stay out of the page's client wasm.
const std = @import("std");
const posts = @import("../../../../blog.zig").posts;

pub const Preview = posts.Preview;

pub fn render(gpa: std.mem.Allocator, markdown: []const u8) !Preview {
    return posts.preview(gpa, markdown);
}

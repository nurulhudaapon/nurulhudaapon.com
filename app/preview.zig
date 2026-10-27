// Standalone wasm for the admin post editor preview: the blog's markdown and
// tree-sitter highlighting, loaded only on that page so other pages' client
// bundle stays small. Driven by `public/post-preview.js`:
// reset -> alloc + copy markdown -> render -> read title/html/minutes.

var arena: std.heap.ArenaAllocator = .init(std.heap.wasm_allocator);
var result: posts.Preview = .{ .title = "", .html = "", .read_minutes = 0 };

export fn preview_reset() void {
    _ = arena.reset(.retain_capacity);
    result = .{ .title = "", .html = "", .read_minutes = 0 };
}

export fn preview_alloc(len: usize) ?[*]u8 {
    const buf = arena.allocator().alloc(u8, len) catch return null;
    return buf.ptr;
}

export fn preview_render(ptr: [*]const u8, len: usize) bool {
    result = posts.renderPreview(arena.allocator(), ptr[0..len]) catch return false;
    return true;
}

export fn preview_title_ptr() [*]const u8 {
    return result.title.ptr;
}

export fn preview_title_len() usize {
    return result.title.len;
}

export fn preview_html_ptr() [*]const u8 {
    return result.html.ptr;
}

export fn preview_html_len() usize {
    return result.html.len;
}

export fn preview_minutes() u32 {
    return result.read_minutes;
}

const std = @import("std");
const posts = @import("pages/blog/posts.zig");

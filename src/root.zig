const std = @import("std");

// BoundedArray was removed from stdlib,
// but is still archived here: https://github.com/jedisct1/zig-bounded-array (thanks!)
// TODO: Consider using ArrayList (or something else) instead.
const BoundedArray = @import("bounded_array.zig").BoundedArray;
const Token = @import("lex.zig").Token;
const syntax = @import("syntax.zig");

const Scout = @import("scout").Scout;
const Pattern = @import("scout").Pattern;

pub const Syntax = struct {
    expression: [2][]const u8,
    statement: [2][]const u8,
    whitespace: ?[]const u8 = null,
};

// Ash template engine.
// Used to compile and render templates.
pub const Engine = struct {
    const Self = @This();

    scout: Scout,

    pub fn init(alloc: std.mem.Allocator, comptime s: Syntax) !Self {
        const expr_begin_ws_size = s.expression[0].len + (s.whitespace orelse "").len;
        const expr_end_ws_size = s.expression[1].len + (s.whitespace orelse "").len;
        const stmt_begin_ws_size = s.statement[0].len + (s.whitespace orelse "").len;
        const stmt_end_ws_size = s.statement[1].len + (s.whitespace orelse "").len;

        // Temporary storage space for the dynamically allocated patterns.
        // These do not have to live beyond the scope of init because Scout will copy anything it needs.
        var expr_begin_ws_buf: [expr_begin_ws_size]u8 = undefined;
        var expr_end_ws_buf: [expr_end_ws_size]u8 = undefined;
        var stmt_begin_ws_buf: [stmt_begin_ws_size]u8 = undefined;
        var stmt_end_ws_buf: [stmt_end_ws_size]u8 = undefined;
        const p = syntax.buildPatterns(s, &expr_begin_ws_buf, &expr_end_ws_buf, &stmt_begin_ws_buf, &stmt_end_ws_buf);

        // TODO: Clarify lifetime requirements in Scout docs.
        const scout = try Scout.init(alloc, .{ .patterns = &p.buffer });
        return .{
            .scout = scout,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scout.deinit();
    }
};

test "engine lifecycle" {
    var engine = try Engine.init(
        std.testing.allocator,
        .{
            .expression = .{ "{{", "}}" },
            .statement = .{ "{#", "#}" },
            .whitespace = "~",
        },
    );
    defer engine.deinit();
}

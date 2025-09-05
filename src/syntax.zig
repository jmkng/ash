const std = @import("std");
const Syntax = @import("root.zig").Syntax;
const BoundedArray = @import("bounded_array.zig").BoundedArray;
const Pattern = @import("scout").Pattern;
const Token = @import("lex.zig").Token;

/// Pass in a series of buffers and receive the built patterns of a syntax.
/// This is a separate function to facilitate testing.
pub fn buildPatterns(
    comptime s: Syntax,
    eb: []u8,
    ee: []u8,
    sb: []u8,
    se: []u8,
) BoundedArray(Pattern, 8) {
    var p = BoundedArray(Pattern, 8).init(0) catch unreachable;
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_begin), .value = s.expression[0] });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_end), .value = s.expression[1] });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_begin), .value = s.statement[0] });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_end), .value = s.statement[1] });
    if (s.whitespace) |ws| {
        _ = std.fmt.bufPrint(eb, "{s}{s}", .{ s.expression[0], ws }) catch unreachable;
        _ = std.fmt.bufPrint(ee, "{s}{s}", .{ ws, s.expression[1] }) catch unreachable;
        _ = std.fmt.bufPrint(sb, "{s}{s}", .{ s.statement[0], ws }) catch unreachable;
        _ = std.fmt.bufPrint(se, "{s}{s}", .{ ws, s.statement[1] }) catch unreachable;
        p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_begin_trim), .value = eb });
        p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_end_trim), .value = ee });
        p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_begin_trim), .value = sb });
        p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_end_trim), .value = se });
    }
    return p;
}

test buildPatterns {
    const s: Syntax = .{
        .expression = .{ "{{", "}}" },
        .statement = .{ "{#", "#}" },
        .whitespace = "~",
    };
    const expr_begin_ws_size = s.expression[0].len + (s.whitespace orelse "").len;
    const expr_end_ws_size = s.expression[1].len + (s.whitespace orelse "").len;
    const stmt_begin_ws_size = s.statement[0].len + (s.whitespace orelse "").len;
    const stmt_end_ws_size = s.statement[1].len + (s.whitespace orelse "").len;
    var expr_begin_ws_buf: [expr_begin_ws_size]u8 = undefined;
    var expr_end_ws_buf: [expr_end_ws_size]u8 = undefined;
    var stmt_begin_ws_buf: [stmt_begin_ws_size]u8 = undefined;
    var stmt_end_ws_buf: [stmt_end_ws_size]u8 = undefined;

    const patterns = buildPatterns(s, &expr_begin_ws_buf, &expr_end_ws_buf, &stmt_begin_ws_buf, &stmt_end_ws_buf);
    try std.testing.expectEqual(8, patterns.len);
    for (patterns.buffer) |pattern| {
        const marker: Marker = @enumFromInt(pattern.id);
        const expected: []const u8 = switch (marker) {
            .expr_begin => "{{",
            .expr_end => "}}",
            .expr_begin_trim => "{{~",
            .expr_end_trim => "~}}",
            .stmt_begin => "{#",
            .stmt_end => "#}",
            .stmt_begin_trim => "{#~",
            .stmt_end_trim => "~#}",
        };
        try std.testing.expect(std.mem.eql(u8, pattern.value, expected));
    }
}

pub const Marker = enum(usize) {
    expr_begin = 0,
    expr_begin_trim = 1,
    expr_end = 2,
    expr_end_trim = 3,
    stmt_begin = 4,
    stmt_begin_trim = 5,
    stmt_end = 6,
    stmt_end_trim = 7,

    /// Return true if the Marker is a whitespace variant.
    pub fn isTrim(self: Marker) bool {
        return switch (self) {
            .expr_begin_trim, .expr_end_trim, .stmt_begin_trim, .stmt_end_trim => true,
            else => false,
        };
    }

    /// Convert the Marker to a lexer Token.
    pub fn toToken(self: Marker) Token {
        return switch (self) {
            .expr_begin, .expr_begin_trim => .expr_begin,
            .expr_end, .expr_end_trim => .expr_end,
            .stmt_begin, .stmt_begin_trim => .stmt_begin,
            .stmt_end, .stmt_end_trim => .stmt_end,
        };
    }
};

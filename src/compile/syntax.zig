const std = @import("std");
const Token = @import("lex.zig").Token;

const Scout = @import("scout").Scout;
const Pattern = @import("scout").Pattern;

/// Identifiers for template markers.
pub const Marker = enum(usize) {
    /// Identifies the beginning of an expression.
    expression_begin = 0,
    /// Identifies the beginning of a whitespace trimmed expression.
    expression_begin_trim = 1,
    /// Identifies the end of an expression.
    expression_end = 2,
    /// Identifies the end of a whitespace trimmed expression.
    expression_end_trim = 3,
    /// Identifies the beginning of a tag.
    tag_begin = 4,
    /// Identifies the beginning of a whitespace trimmed tag.
    tag_begin_trim = 5,
    /// Identifies the end of a tag.
    tag_end = 6,
    /// Identifies the end of a whitespace trimmed tag.
    tag_end_trim = 7,

    /// Return true if the `Marker` is a whitespce trim variant.
    pub fn isTrim(self: Marker) bool {
        return switch (self) {
            .expression_begin_trim, .expression_end_trim, .tag_begin_trim, .tag_end_trim => true,
            else => false,
        };
    }

    /// Convert the `Marker` to a `Token`.
    pub fn toToken(self: Marker) Token {
        return switch (self) {
            .expression_begin, .expression_begin_trim => .expression_begin,
            .expression_end, .expression_end_trim => .expression_end,
            .tag_begin, .tag_begin_trim => .tag_begin,
            .tag_end, .tag_end_trim => .tag_end,
        };
    }
};

/// Builds a template syntax used to initialize `Ash`.
pub const Builder = struct {
    /// Storage for markers used to build expression patterns.
    expression_markers: ?[2][]const u8 = null,
    /// Storage for markers used to build tag patterns.
    tag_markers: ?[2][]const u8 = null,
    /// Storage for a marker used to build whitespace patterns.
    whitespace_marker: ?[]const u8 = null,

    /// Set the expression markers.
    ///
    /// Expressions allow you to render data saved in a `Store`,
    /// or literal values like strings and numbers.
    ///
    /// They are also used to call filter functions.
    ///
    /// If you don't provide expression markers using this method,
    /// expressions are not available.
    ///
    /// # Example
    ///
    /// Expression Markers: "{{", "}}",
    ///
    /// Render a variable from the `Store`:
    ///
    /// {{ name }} // ash
    ///
    /// Render a variable from the `Store` and transform it with filters:
    ///
    /// {{ name | uppercase }} // ASH
    ///
    /// Render a literal value and transform it with filters:
    ///
    /// {{ "ash" | uppercase | left 1 }} // A
    pub fn expression(self: *Builder, beginning: []const u8, end: []const u8) void {
        if (self.expression_markers == null) self.expression_markers = undefined;
        self.expression_markers.?[0] = beginning;
        self.expression_markers.?[1] = end;
    }

    /// Set the tag markers.
    ///
    /// Tags provide the logic and control flow in templates.
    /// They do not cause any output to be generated on their own.
    ///
    /// # Example
    ///
    /// Tag Markers: "{#", "#}"
    ///
    /// If blocks allow conditional rendering:
    ///
    /// {# if name == "ash" -#}
    ///     Ash
    /// {# else if name == "sif" #}
    ///     Sif
    /// {# else #}
    ///     Default
    /// {# end #}
    pub fn tag(self: *Builder, beginning: []const u8, end: []const u8) void {
        if (self.tag_markers == null) self.tag_markers = undefined;
        self.tag_markers.?[0] = beginning;
        self.tag_markers.?[1] = end;
    }

    /// Set the whitespace trim marker.
    ///
    /// This is a byte that can be attached to an expression or tag marker,
    /// and it causes whitespace on that side to be removed.
    ///
    /// # Example
    ///
    /// Expression Markers:     "{{", "}},
    /// Tag Markers:            "{#", "#}"
    /// Whitespace Markers:     "~"
    ///
    /// The whitespace byte was set to "~", so trim the whitespace before an
    /// expression like this:
    ///
    /// "{{~"
    ///
    /// And trim the whitespace after a tag like this:
    ///
    /// "~#}"
    pub fn whitespace(self: *Builder, value: []const u8) void {
        self.whitespace_marker = value;
    }

    /// Return a `Syntax` from the markers in this `Builder`.
    ///
    /// You do not normally need to call this method to initialize `Ash`,
    /// instead pass the `Builder` directly to `Ash.init`.
    ///
    /// If you do use this method for any reason, you must deinitialize
    /// the `Syntax` using `deinit`.
    pub fn syntax(self: *Builder, allocator: std.mem.Allocator) !Syntax {
        var patterns = std.ArrayList(Pattern).empty;
        var dynamic = std.ArrayList([]u8).empty;

        if (self.expression_markers) |exp| {
            if (self.whitespace_marker) |ws| { // _dynamic
                const b_exp_c = try std.fmt.allocPrint(allocator, "{s}{s}", .{ exp[0], ws });
                const e_exp_c = try std.fmt.allocPrint(allocator, "{s}{s}", .{ ws, exp[1] });
                const b_exp_p = Pattern{ .id = @intFromEnum(Marker.expression_begin_trim), .value = b_exp_c };
                const e_exp_p = Pattern{ .id = @intFromEnum(Marker.expression_end_trim), .value = e_exp_c };
                try dynamic.append(allocator, b_exp_c);
                try dynamic.append(allocator, e_exp_c);
                try patterns.append(allocator, b_exp_p);
                try patterns.append(allocator, e_exp_p);
            }
            const b_exp = Pattern{ .id = @intFromEnum(Marker.expression_begin), .value = exp[0] };
            const e_exp = Pattern{ .id = @intFromEnum(Marker.expression_end), .value = exp[1] };
            try patterns.append(allocator, b_exp);
            try patterns.append(allocator, e_exp);
        }
        if (self.tag_markers) |blk| {
            if (self.whitespace_marker) |ws| { // _dynamic
                const b_tag_c = try std.fmt.allocPrint(allocator, "{s}{s}", .{ blk[0], ws });
                const e_tag_c = try std.fmt.allocPrint(allocator, "{s}{s}", .{ ws, blk[1] });
                const b_tag_p = Pattern{ .id = @intFromEnum(Marker.tag_begin_trim), .value = b_tag_c };
                const e_tag_p = Pattern{ .id = @intFromEnum(Marker.tag_end_trim), .value = e_tag_c };
                try dynamic.append(allocator, b_tag_c);
                try dynamic.append(allocator, e_tag_c);
                try patterns.append(allocator, b_tag_p);
                try patterns.append(allocator, e_tag_p);
            }
            const b_tag = Pattern{ .id = @intFromEnum(Marker.tag_begin), .value = blk[0] };
            const e_tag = Pattern{ .id = @intFromEnum(Marker.tag_end), .value = blk[1] };
            try patterns.append(allocator, b_tag);
            try patterns.append(allocator, e_tag);
        }

        const p = try patterns.toOwnedSlice(allocator);
        const d = try dynamic.toOwnedSlice(allocator);
        return .{ .allocator = allocator, .patterns = p, ._dynamic = d };
    }
};

/// Contains a set of patterns that `Ash` will use to parse templates.
const Syntax = struct {
    allocator: std.mem.Allocator,
    /// Patterns available within this `Syntax`.
    ///
    /// Each `Pattern` has a `[]const u8` inside of it, and we don't copy or take ownership
    /// of that at all, except in the case of dynamically generated values which are tracked
    /// by the `dynamic` field.
    ///
    /// This is because it is assumed that the values passed in to `Builder` are
    /// going to be hardcoded bytes, which live in static memory.
    patterns: []Pattern,
    /// Slices to dynamic patterns generated by a `Builder`.
    _dynamic: [][]u8,

    /// Release all allocated memory.
    pub fn deinit(self: *Syntax) void {
        for (self._dynamic) |gm| self.allocator.free(gm);
        self.allocator.free(self.patterns);
        self.allocator.free(self._dynamic);
    }
};

const testing = std.testing;

test "builder syntax" {
    var builder = Builder{};
    builder.expression("{{", "}}");
    builder.tag("{#", "#}");
    builder.whitespace("~");
    var syntax = try builder.syntax(testing.allocator);
    defer syntax.deinit();

    try testing.expectEqual(8, syntax.patterns.len);
    for (syntax.patterns) |pattern| {
        const marker: Marker = @enumFromInt(pattern.id);
        const expected: []const u8 = switch (marker) {
            .expression_begin => "{{",
            .expression_end => "}}",
            .expression_begin_trim => "{{~",
            .expression_end_trim => "~}}",
            .tag_begin => "{#",
            .tag_end => "#}",
            .tag_begin_trim => "{#~",
            .tag_end_trim => "~#}",
        };
        try testing.expect(std.mem.eql(u8, pattern.value, expected));
    }
}

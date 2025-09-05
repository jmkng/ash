const std = @import("std");

const Marker = @import("syntax.zig").Marker;
const BoundedArray = @import("bounded_array.zig").BoundedArray;
const Pointer = @import("error.zig").Pointer;
const Region = @import("error.zig").Region;

const Scout = @import("scout").Scout;
const Pattern = @import("scout").Pattern;
const ziglyph = @import("ziglyph"); // TODO: Switch to zg.

// Abstracting over ziglyph's iterator type here,
// hopefully making migration to zg easier.

/// Grapheme yielded by GraphemeIterator.
const Grapheme = struct {
    /// Byte length.
    len: usize,
    /// Offset relative to iterator source provided in GraphemeIterator.init.
    offset: usize,
    /// The source bytes provided to the GraphemeIterator that created this Grapheme.
    iterator_bytes: []const u8,

    /// Return a view of the bytes in this Grapheme.
    pub fn slice(self: Grapheme) []const u8 {
        return self.iterator_bytes[self.offset .. self.offset + self.len];
    }
};

/// Produces a stream of unicode graphemes from bytes.
/// Create one with init.
const GraphemeIterator = struct {
    const Self = @This();

    bytes: []const u8,
    pos: usize = 0,
    zg: ziglyph.GraphemeIterator,

    pub fn init(bytes: []const u8) Self {
        return .{
            .bytes = bytes,
            .zg = ziglyph.GraphemeIterator.init(bytes),
        };
    }

    /// Return the next Grapheme, or null if the iterator is exhausted.
    pub fn next(self: *Self) ?Grapheme {
        const zgg = self.zg.next() orelse return null;
        self.pos = zgg.offset + zgg.len;

        return .{
            .len = zgg.len,
            .offset = zgg.offset,
            .iterator_bytes = self.bytes,
        };
    }

    pub fn peekByte(self: *Self) ?u8 {
        if (self.pos >= self.bytes.len) return null;
        return self.bytes[self.pos];
    }
};
test GraphemeIterator {
    var g1 = GraphemeIterator.init("");
    try std.testing.expectEqual(0, g1.pos);
    try std.testing.expectEqual(null, g1.next());
    try std.testing.expectEqual(null, g1.peekByte());

    const g2_bytes = "a b";
    var g2 = GraphemeIterator.init(g2_bytes);
    try std.testing.expectEqual(0, g2.pos);
    try std.testing.expectEqual('a', g2.peekByte());
    try std.testing.expectEqual('a', g2.peekByte());
    try std.testing.expectEqualSlices(u8, "a", g2.next().?.slice());
    try std.testing.expectEqual(' ', g2.peekByte());
    try std.testing.expectEqual(' ', g2.peekByte());
    try std.testing.expectEqualSlices(u8, " ", g2.next().?.slice());
    try std.testing.expectEqual('b', g2.peekByte());
    try std.testing.expectEqual('b', g2.peekByte());
    try std.testing.expectEqualSlices(u8, "b", g2.next().?.slice());
    try std.testing.expectEqual(null, g2.peekByte());
    try std.testing.expectEqual(null, g2.peekByte());
    try std.testing.expectEqual(null, g2.next());
    try std.testing.expectEqual(null, g2.next());
}

const CompileError = error{
    InvalidTemplate,
    InvalidUtf8,
};

pub const Diagnostic = struct {
    const Self = @This();

    reason: []const u8 = "",
    pointer: ?Pointer = null,
    help: ?[]const u8 = "",
    name: ?[]const u8 = "",

    pub fn write(self: Self, w: *std.Io.Writer, o: struct { color: bool = false }) !void {
        // TODO: Use color when enabled.
        _ = o; // autofix

        if (self.name) |n| try w.print("{s}", .{n});
        if (self.name != null and self.pointer != null) _ = try w.write(":");
        if (self.pointer) |p| {
            try p.write(w);
        } else {
            _ = try w.write("\n");
        }
        if (self.help) |h| try w.print("{s}\n", .{h});
    }
};

const Source = struct {
    bytes: []const u8,
    pos: usize = 0,
};

/// Lexer options.
/// Provide a Diagnostic to receive expanded error information when Lexer.next fails.
pub const NextOpts = struct {
    diagnostic: ?*Diagnostic = null,
};

pub const Lexer = struct {
    const Self = @This();

    /// The source text and current position.
    source: Source,
    /// Buffered token storage.
    /// Sometimes the lexer encounters a situation where it must lex a type,
    /// but it also aware of what the next token type is.
    /// In that case, the next one is stored here to be immediately read.
    buffer: ?TokenRegion = null,
    /// Tool for finding template markers.
    marker_finder: Scout,
    /// Trim the next leftside whitespace?
    left_trim: bool = false,
    /// State.
    state: LexerState = .default,
    /// Makes the Lexer more flexible by disabling some assertions,
    /// and allowing it to return null in certain calls to Lexer.next
    /// which would usually return an error.
    is_test_lexer: bool = false,

    /// Return a new Lexer.
    /// This Lexer will own the provided Scout.
    /// Caller must use Lexer.deinit.
    pub fn init(bytes: []const u8, s: Scout) Lexer {
        return .{
            .source = .{ .bytes = bytes },
            .marker_finder = s,
        };
    }

    pub fn deinit(self: *Self) void {
        self.marker_finder.deinit();
    }

    /// Return the next TokenRegion.
    pub fn next(self: *Self, o: NextOpts) CompileError!?TokenRegion {
        while (true) {
            // Always take from the buffer when possible.
            if (self.buffer) |buf| {
                self.buffer = null;
                return buf;
            }

            // Abort if the source is exhausted.
            const remaining = self.source.bytes[self.source.pos..];
            if (remaining.len == 0) {
                switch (self.state) {
                    .default => return null,
                    .inside => {
                        // Treat this as a simple end of stream in tests.
                        if (self.is_test_lexer) return null;

                        if (o.diagnostic) |d| {
                            const region = Region{ .begin = self.source.pos, .end = self.source.bytes.len };
                            d.reason = "unexpected end of source";
                            d.pointer = region.pointer(self.source.bytes);
                            d.help = "block is not closed";
                        }
                        return CompileError.InvalidTemplate;
                    },
                }
            }

            const token_region: ?TokenRegion = try switch (self.state) {
                .default => self.default(o.diagnostic),
                .inside => |expected_end_token| self.inside(expected_end_token, o.diagnostic),
            } orelse {
                return null;
            };

            if (token_region.?.token == .whitespace) continue;
            return token_region;
        }
    }

    /// Entry point #1.
    fn default(self: *Self, dx: ?*Diagnostic) CompileError!?TokenRegion {
        const from = self.source.pos;

        const next_location = self.marker_finder.next(self.source.bytes, self.source.pos) orelse {
            // No markers left, return a raw token over the remaining region.
            const end: usize = self.source.bytes.len;
            self.source.pos = end;
            return self.trimRawTokenRegion(Region{ .begin = from, .end = end }, false);
        };

        // Found a marker. What token does it represent?
        const marker: Marker = @enumFromInt(next_location.match.id);
        const is_trim = marker.isTrim();
        const token = marker.toToken();

        switch (token) {
            .expr_begin => self.state = .{ .inside = .expr_end },
            .stmt_begin => self.state = .{ .inside = .stmt_end },
            else => {
                if (dx) |d| {
                    const region = Region{ .begin = next_location.beginning(), .end = next_location.end };
                    d.reason = "unexpected token";
                    d.pointer = region.pointer(self.source.bytes);
                    d.help = "expected beginning of expression or statement";
                }
                return error.InvalidTemplate;
            },
        }

        // Advance position to the end of the marker.
        self.source.pos = next_location.end;

        if (from != next_location.beginning()) {
            // The location of the next marker is known,
            // but it isn't the next thing to read. Store the location in the buffer
            // and read this chunk of raw text first.
            self.buffer = .{
                .token = token,
                .region = .{ .begin = next_location.beginning(), .end = next_location.end },
            };

            return self.trimRawTokenRegion(.{
                .begin = from,
                .end = next_location.beginning(),
            }, is_trim);
        }

        const region: Region = .{ .begin = next_location.beginning(), .end = next_location.end };
        return .{ .token = token, .region = region };
    }

    /// Entry point #2.
    fn inside(self: *Self, expected_end_token: Token, dx: ?*Diagnostic) CompileError!?TokenRegion {
        _ = expected_end_token; // autofix

        if (!self.is_test_lexer) std.debug.assert(self.source.pos > 0);

        const from: usize = self.source.pos;
        const remaining = self.source.bytes[from..];

        // This first branch is responsible for detecting the end of the block.
        if (self.marker_finder.starts(self.source.bytes, from)) |result| {
            _ = result; // autofix
            @panic("TODO: handle end of block in inside state");
        }

        var iter = GraphemeIterator.init(remaining);
        const grapheme = iter.next() orelse unreachable;
        const grapheme_bytes = grapheme.slice();
        const grapheme_first_byte = grapheme_bytes[0];

        var tok: ?Token = null;
        switch (grapheme_first_byte) {
            '*' => tok = Token{ .operator = Operator.multiply },
            '+' => tok = Token{ .operator = Operator.add },
            '/' => tok = Token{ .operator = Operator.divide },
            '-' => tok = Token{ .operator = Operator.subtract },
            '.' => tok = Token.period,
            ',' => tok = Token.comma,
            ':' => tok = Token.colon,
            '0'...'9' => return self.munchNumber(&iter, from),
            else => {},
        }
        if (tok != null) {
            self.source.pos += 1;
            return TokenRegion{ .token = tok.?, .region = .{ .begin = from, .end = from + 1 } };
        }

        switch (grapheme_first_byte) {
            '"' => return self.munchString(&iter, from),
            '=', '!', '>', '<', '|', '&' => @panic("todo: lex operator"),
            else => {},
        }

        if (try isWhitespaceU(grapheme_bytes)) {
            return try self.munchWhitespace(&iter, from);
        }

        if (dx) |d| {
            d.reason = "unexpected token";
            const region = Region{ .begin = from, .end = from + grapheme.len };
            d.pointer = region.pointer(self.source.bytes);
        }

        return error.InvalidTemplate;
    }

    /// Munch a number.
    /// Iterates until a non-decimal digit is found.
    fn munchNumber(self: *Self, iter: *GraphemeIterator, from: usize) TokenRegion {
        var end = from + 1;

        while (iter.next()) |grapheme| {
            const grapheme_bytes = grapheme.slice();
            const grapheme_first_byte = grapheme_bytes[0];

            switch (grapheme_first_byte) {
                '0'...'9' => {
                    end = from + grapheme.offset + 1;
                },
                '_' => {
                    const peeked = iter.peekByte();
                    if (peeked == null or !std.ascii.isDigit(peeked.?)) break;

                    end = from + grapheme.offset + grapheme.len;
                },
                else => break,
            }
        }

        self.source.pos = end;
        return TokenRegion{
            .token = Token.number,
            .region = Region{ .begin = from, .end = end },
        };
    }

    /// Munch a string literal.
    /// Iterates until an unescaped double quote is found.
    fn munchString(self: *Self, iter: *GraphemeIterator, from: usize) TokenRegion {
        var end = from + 1;
        var is_escaped = false;

        while (iter.next()) |grapheme| {
            const grapheme_bytes = grapheme.slice();
            const grapheme_first_byte = grapheme_bytes[0];
            end = from + grapheme.offset + grapheme.len;

            self.source.pos = end;
            if (grapheme_first_byte == '\\') {
                is_escaped = true;
            }
            if (grapheme_first_byte == '"') break;
        }

        return TokenRegion{
            .token = .string,
            .region = Region{ .begin = from, .end = end },
        };
    }

    /// Munch whitespace.
    /// Iterates until a non-whitespace character is found.
    fn munchWhitespace(self: *Self, iter: *GraphemeIterator, from: usize) error{InvalidUtf8}!TokenRegion {
        var end = from + 1;
        while (iter.next()) |grapheme| {
            const grapheme_bytes = grapheme.slice();
            if (!(try isWhitespaceU(grapheme_bytes))) break;
            end = from + grapheme.offset + grapheme.len;
        }

        self.source.pos = end;
        return .{
            .token = .whitespace,
            .region = .{ .begin = from, .end = end },
        };
    }

    /// Return a TokenRegion containing Token.raw and a trimmed region.
    fn trimRawTokenRegion(self: *Self, region: Region, right_trim: bool) TokenRegion {
        var trimmed_region = region;
        if (right_trim)
            trimmed_region.end = std.mem.trimRight(u8, self.source.bytes[0..region.end], &std.ascii.whitespace).len;
        if (self.left_trim) {
            self.left_trim = false;
            const s = self.source.bytes[region.begin..trimmed_region.end];
            trimmed_region.begin = region.begin + s.len - std.mem.trimLeft(u8, s, &std.ascii.whitespace).len;
        }

        return .{ .token = .raw, .region = trimmed_region };
    }
}; // Lexer

const LexerStateTag = enum {
    default,
    inside,
};

const LexerState = union(LexerStateTag) {
    default: void,
    /// Lexer is inside of a tag.
    /// Contains the expected end Token.
    inside: Token,
};

pub const TokenRegion = struct {
    token: Token,
    region: Region,
};

const Keyword = enum {
    @"or",
    @"and",
    @"if",
    @"else",
    @"var",
    @"const",
    @"for",
    template,
    extend,
    @"break",
    @"continue",
    end,
};

const Operator = enum {
    add,
    subtract,
    multiply,
    divide,
    greater,
    lesser,
    equal,
    not_equal,
    greater_or_equal,
    lesser_or_equal,
};

pub const Token = union(enum) {
    raw,
    string,
    number,
    identifier,
    whitespace,
    expr_begin,
    expr_end,
    stmt_begin,
    stmt_end,
    period,
    comma,
    pipe,
    true,
    false,
    exclamation,
    colon,
    keyword: Keyword,
    operator: Operator,
};

/// Return true if the bytes are entirely whitespace.
/// Asserts that the bytes are valid UTF-8.
/// Unicode-aware.
fn isWhitespaceU(utf8_bytes: []const u8) !bool {
    if (utf8_bytes.len == 0) return false;
    var view = try std.unicode.Utf8View.init(utf8_bytes);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |cp| {
        if (!ziglyph.isWhiteSpace(cp)) {
            return false;
        }
    }

    return true;
}
test isWhitespaceU {
    try std.testing.expect((try isWhitespaceU("\t")));
    try std.testing.expect((try isWhitespaceU("   \u{2009}")));
    try std.testing.expect((try isWhitespaceU(" ")));
    try std.testing.expect(!(try isWhitespaceU("  a")));
}

const TestCase = struct {
    bytes: []const u8,
    want: Region,
    pos: ?usize = null,
};

test "state transitions" {
    var lexer = initTestLexer("a {{");
    defer lexer.deinit();

    const reg1 = [_]TokenRegion{
        .{ .token = .raw, .region = .{ .begin = 0, .end = 2 } },
        .{ .token = .expr_begin, .region = .{ .begin = 2, .end = 4 } },
    };
    for (reg1) |r| {
        try std.testing.expectEqual(r, lexer.next(NextOpts{}));
    }
    try std.testing.expectEqual(4, lexer.source.pos);
    try std.testing.expectEqual(LexerState{ .inside = Token.expr_end }, lexer.state);

    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
}

test "munch raw" {
    var lexer = initTestLexer("hello world");
    defer lexer.deinit();

    const reg1 = [_]TokenRegion{
        .{ .token = .raw, .region = .{ .begin = 0, .end = 11 } },
    };
    for (reg1) |r| {
        try std.testing.expectEqual(r, lexer.next(NextOpts{}));
    }
    try std.testing.expectEqual(11, lexer.source.pos);

    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
}

test "character recognition" {
    const bytes = "*+/-.,:";
    var lexer = initTestLexer(bytes);
    defer lexer.deinit();
    lexer.state = .{ .inside = .expr_end };

    const reg1 = [_]TokenRegion{
        .{ .token = .{ .operator = .multiply }, .region = .{ .begin = 0, .end = 1 } },
        .{ .token = .{ .operator = .add }, .region = .{ .begin = 1, .end = 2 } },
        .{ .token = .{ .operator = .divide }, .region = .{ .begin = 2, .end = 3 } },
        .{ .token = .{ .operator = .subtract }, .region = .{ .begin = 3, .end = 4 } },
        .{ .token = .period, .region = .{ .begin = 4, .end = 5 } },
        .{ .token = .comma, .region = .{ .begin = 5, .end = 6 } },
        .{ .token = .colon, .region = .{ .begin = 6, .end = 7 } },
    };
    var i: usize = 1;
    for (reg1) |r| {
        try std.testing.expectEqual(r, lexer.next(NextOpts{}));
        try std.testing.expectEqual(i, lexer.source.pos);
        i += 1;
    }
    try std.testing.expectEqual(7, lexer.source.pos);
    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
    try std.testing.expectEqual(null, lexer.next(NextOpts{}));
}

test "munch whitespace" {
    const reg1 = [_]TestCase{
        .{
            .bytes = " ",
            .want = .{ .begin = 0, .end = 1 },
        },
        .{
            .bytes = " \u{2004} ",
            .want = .{ .begin = 0, .end = 5 },
        },
    };

    for (reg1) |r| {
        var lexer = initTestLexer(r.bytes);
        defer lexer.deinit();
        lexer.state = .{ .inside = .expr_end };
        var gi = GraphemeIterator.init(r.bytes);
        try std.testing.expectEqual(
            TokenRegion{ .token = .whitespace, .region = r.want },
            lexer.munchWhitespace(&gi, r.want.begin),
        );
        try std.testing.expectEqual(r.pos orelse r.bytes.len, lexer.source.pos);
    }
}

test "munch string literal" {
    const long_string = "allo 🐻 1234567890 `~!@#$%^&*()_+[{]} \\ |:;',<.>/?\"";
    const reg1 = [_]TestCase{
        .{
            .bytes = "a\" beyond string~",
            .want = .{ .begin = 0, .end = 2 },
            .pos = 2,
        },
        .{
            .bytes = long_string,
            .want = .{ .begin = 0, .end = 53 },
        },
    };

    for (reg1) |r| {
        var lexer = initTestLexer(r.bytes);
        defer lexer.deinit();
        lexer.state = .{ .inside = .expr_end };
        var gi = GraphemeIterator.init(r.bytes);
        try std.testing.expectEqual(
            TokenRegion{ .token = .string, .region = r.want },
            lexer.munchString(&gi, r.want.begin),
        );
        try std.testing.expectEqual(r.pos orelse r.bytes.len, lexer.source.pos);
    }
}

test "munch number" {
    const reg1 = [_]TestCase{
        .{
            .bytes = "1",
            .want = .{ .begin = 0, .end = 1 },
        },
        .{
            .bytes = "12",
            .want = .{ .begin = 0, .end = 2 },
        },
        .{
            .bytes = "100_000",
            .want = .{ .begin = 0, .end = 7 },
        },
    };

    for (reg1) |r| {
        var lexer1 = initTestLexer(r.bytes);
        lexer1.deinit();
        lexer1.state = .{ .inside = .expr_end };
        var gi = GraphemeIterator.init(r.bytes);
        try std.testing.expectEqual(
            TokenRegion{ .token = .number, .region = r.want },
            lexer1.munchNumber(&gi, r.want.begin),
        );
        try std.testing.expectEqual(r.pos orelse r.bytes.len, lexer1.source.pos);
    }

    // Trailing digit separator should not be seen as part of number.
    const reg2_bytes = "100_000_";
    var lexer2 = initTestLexer(reg2_bytes);
    defer lexer2.deinit();
    lexer2.state = .{ .inside = .expr_end };

    var gi = GraphemeIterator.init(reg2_bytes);
    try std.testing.expectEqual(
        TokenRegion{
            .token = .number,
            .region = .{ .begin = 0, .end = 7 },
        },
        lexer2.munchNumber(&gi, 0),
    );
    try std.testing.expectEqual(7, lexer2.source.pos);
}

/// Returns a Lexer with a predefined syntax.
/// The lexer uses the testing allocator.
/// Caller must use deinit.
fn initTestLexer(source: []const u8) Lexer {
    var p = BoundedArray(Pattern, 8).init(0) catch unreachable;
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_begin), .value = "{{" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_end), .value = "}}" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_begin), .value = "{#" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_end), .value = "#}" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_begin_trim), .value = "{{~" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.expr_end_trim), .value = "~}}" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_begin_trim), .value = "{#~" });
    p.appendAssumeCapacity(.{ .id = @intFromEnum(Marker.stmt_end_trim), .value = "~#}" });

    const scout = Scout.init(std.testing.allocator, .{ .patterns = p.slice() }) catch unreachable;
    var lexer = Lexer.init(source, scout);
    lexer.is_test_lexer = true;
    return lexer;
}

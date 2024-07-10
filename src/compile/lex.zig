const std = @import("std");
const ascii = std.ascii;

const Marker = @import("syntax.zig").Marker;
const Builder = @import("syntax.zig").Builder;

const Scout = @import("scout").Scout;
const Pattern = @import("scout").Pattern;

/// Provides an iterator for `Token` from a slice of bytes.
pub const Lexer = struct {
    source: SourceState,
    buffer: ?Pair = null,
    trim: TrimState,
    state: LexerState = .default,

    /// A compiled `Scout` used to scan for template markers.
    scanner: Scout,

    /// Return a new `Lexer`.
    pub fn init(source: []const u8, scanner: Scout) Lexer {
        return .{ .source = .{ .slice = source }, .trim = .{ .source = source }, .scanner = scanner };
    }

    /// Parameters for `Lexer.next`.
    const NextParams = struct {
        /// Skip all whitespace.
        skip_whitespace: bool = false,
    };

    /// Return a `Pair` for the next non-whitespace token.
    pub fn next(self: *Lexer, params: NextParams) !?Pair {
        while (true) {
            if (self.buffer) |buf| { // Prefer pulling from the buffer.
                self.buffer = null;
                return buf;
            }
            if (self.text()[self.cursor()..].len == 0) return null;

            const result = try switch (self.state) {
                .default => |*d| d.lex(self),
                .inside => |*i| i.lex(self),
            };
            if (result == null) return null;

            if (result.?.token == .whitespace and params.skip_whitespace) continue;
            return result.?;
        }
    }

    /// Return the cursor position.
    pub fn cursor(self: Lexer) usize {
        return self.source.pos;
    }

    /// Return the source text.
    pub fn text(self: Lexer) []const u8 {
        return self.source.slice;
    }
};

/// Contains the source text and current position.
pub const SourceState = struct {
    /// The source text.
    slice: []const u8,
    /// Index position within the source text.
    pos: usize = 0,
};

/// Parameters for `TrimState.toPair`.
const TrimParams = struct {
    /// The `Token` to place in the `Pair`.
    token: Token = .raw,
    /// when true, the `Region` in the new `Pair` will disregard the whitespace
    /// after it.
    right_trim: bool = false,
};

/// Controls the whitespace trimming behavior.
pub const TrimState = struct {
    /// The source text.
    source: []const u8,
    /// When true, the following `Pair` created by `TrimState.toPair` will be left trimmed.
    left_trim: bool = false,

    /// Return a `Pair` from the `Region`.
    fn toPair(self: *TrimState, region: Region, params: TrimParams) !?Pair {
        var result = region;
        if (params.right_trim)
            result.end = std.mem.trimRight(u8, self.source[0..region.end], &ascii.whitespace).len;
        if (self.left_trim) {
            self.left_trim = false;
            const s = self.source[region.begin..result.end];
            result.begin = region.begin + s.len - std.mem.trimLeft(u8, s, &ascii.whitespace).len;
        }

        return .{ .token = params.token, .region = result };
    }
};

/// A combined `Token` and `Region`.
pub const Pair = struct {
    /// The `Token` related to the `Pair`.
    token: Token,
    /// The `Region` related to the `Pair`.
    region: Region,
};

/// The state of a `Lexer`.
pub const LexerState = union(enum) {
    /// Default state.
    default: DefaultState,
    /// Inside of a tag.
    inside: InsideState,
};

pub const DefaultState = struct {
    // Lex a `Pair` in default state.
    pub fn lex(_: *DefaultState, lexer: *Lexer) !?Pair {
        const from = lexer.cursor();
        const text = lexer.text();

        const next = lexer.scanner.next(text, from);
        if (next == null) {
            const end: usize = text.len;
            lexer.source.pos = text.len;
            const region = Region{ .begin = from, .end = end };
            return lexer.trim.toPair(region, .{});
        }

        const location = next.?;
        const marker: Marker = @enumFromInt(location.match.id);
        const is_trim = marker.isTrim();
        const token = marker.toToken();
        switch (token) {
            .expression_begin => lexer.state = .{ .inside = .{ .end_token = .expression_end } },
            .tag_begin => lexer.state = .{ .inside = .{ .end_token = .tag_end } },
            else => @panic("expected expression/tag beginning"), // Return error
        }

        lexer.source.pos = location.end;
        if (from != location.beginning()) {
            lexer.source.pos = location.end;
            lexer.buffer = .{
                .token = token,
                .region = .{ .begin = location.beginning(), .end = location.end },
            };
            return lexer.trim.toPair(.{
                .begin = from,
                .end = location.beginning(),
            }, .{ .right_trim = is_trim });
        }
        const region: Region = .{ .begin = location.beginning(), .end = location.end };
        return .{ .token = token, .region = region };
    }
};

pub const InsideState = struct {
    /// The expected end token.
    end_token: Token,

    // Lex a `Pair` in inside state.
    pub fn lex(_: *InsideState, _: *Lexer) !?Pair {
        @panic("todo: lex inside");
    }
};

/// Points to an area in source text.
pub const Region = struct {
    /// The beginning index of the range, inclusive.
    begin: usize,
    /// the ending index of the range, exclusive.
    end: usize,
};

pub const Keyword = enum {
    /// "or"
    @"or",
    /// "and"
    @"and",
    /// "if"
    @"if",
    /// "else"
    @"else",
    /// "var"
    @"var",
    /// "const"
    @"const",
    /// "for"
    @"for",
    /// "template"
    template,
    /// "extend"
    extend,
    /// "break"
    @"break",
    /// "continue"
    @"continue",
    /// "end"
    end,

    pub fn toString(self: Keyword) []const u8 {
        switch (self) {
            .@"or" => "or",
            .@"and" => "and",
            .@"if" => "if",
            .@"else" => "else",
            .@"var" => "var",
            .@"const" => "const",
            .@"for" => "for",
            .template => "template",
            .extend => "extend",
            .@"break" => "break",
            .@"continue" => "continue",
            .end => "end",
        }
    }
};

pub const Operator = enum {
    /// "+"
    add,
    /// "-"
    subtract,
    /// "\*"
    multiply,
    /// "/"
    divide,
    /// ">"
    greater,
    /// "<"
    lesser,
    /// "="
    equal,
    /// "!="
    not_equal,
    /// ">="
    greater_or_equal,
    /// "<="
    lesser_or_equal,

    pub fn toString(self: Operator) []const u8 {
        switch (self) {
            .add => "+",
            .subtract => "-",
            .multiply => "*",
            .divide => "/",
            .greater => ">",
            .lesser => "<",
            .equal => "=",
            .not_equal => "!=",
            .greater_or_equal => ">=",
            .lesser_or_equal => "<=",
        }
    }
};

/// Tokens generated by `Lexer`.
pub const Token = union(enum) {
    /// Raw text.
    raw,
    /// String literal.
    string,
    /// Number literal.
    number,
    /// Identifier (unquoted string).
    identifier,
    /// Whitespace.
    whitespace,
    /// Expression beginning.
    expression_begin,
    /// Expression ending.
    expression_end,
    /// Tag beginning.
    tag_begin,
    /// Tag ending.
    tag_end,
    /// "."
    period,
    /// ","
    comma,
    /// "|"
    pipe,
    /// "true"
    true,
    /// "false"
    false,
    /// "!"
    exclamation,
    /// :
    colon,

    keyword: Keyword,
    operator: Operator,

    pub fn toString(self: Token) []const u8 {
        return switch (self) {
            .raw => "raw",
            .string => "string",
            .number => "number",
            .identifier => "identifier",
            .whitespace => "whitespace",
            .expression_begin => "expression begin",
            .expression_end => "expression end",
            .tag_begin => "tag begin",
            .tag_end => "tag ending",
            .period => ".",
            .comma => ",",
            .pipe => "|",
            .true => "true",
            .false => "false",
            .exclamation => "!",
            .colon => ":",
            .keyword => |kw| kw.toString(),
            .operator => |op| op.toString(),
        };
    }
};

const testing = std.testing;

test "lexer raw" {
    var expect = [_]Pair{
        .{ .token = .raw, .region = .{ .begin = 0, .end = 11 } },
    };
    _ = try t(testing.allocator, "hello world", &expect);
}

test "lexer expression" {
    var pairs = [_]Pair{
        Pair{ .token = .raw, .region = Region{ .begin = 0, .end = 6 } },
        Pair{ .token = .expression_begin, .region = Region{ .begin = 6, .end = 8 } },
    };
    _ = try t(testing.allocator, "hello {{", &pairs);
}

fn t(allocator: std.mem.Allocator, source: []const u8, expect: []Pair) !Lexer {
    var b = Builder{};
    b.expression("{{", "}}");
    b.tag("{#", "#}");
    b.whitespace("~");

    var s = try b.syntax(allocator);
    defer s.deinit();
    const patterns = s.patterns;
    var scout = try Scout.init(allocator, .{ .patterns = patterns });
    defer scout.deinit();

    var lexer = Lexer.init(source, scout);
    for (expect) |pair| {
        try testing.expectEqual(pair, try lexer.next(.{}));
    }
    // Exhaust the lexer.
    try testing.expectEqual(null, lexer.next(.{}));
    try testing.expectEqual(null, lexer.next(.{}));
    try testing.expectEqual(null, lexer.next(.{}));
    return lexer;
}

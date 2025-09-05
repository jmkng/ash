const std = @import("std");

const RED: []const u8 = "\x1b[31m";
const RESET: []const u8 = "\x1b[0m";

const SPACE: u8 = ' ';
const PIPE: u8 = '|';
const EQUAL: u8 = '=';
const CARET: u8 = '^';

pub const Pointer = struct {
    const Self = @This();

    /// The highlighted line within the source text.
    line: []const u8,
    /// Line number.
    /// This value will always be at least 1.
    line_num: usize,
    /// Begin index of Region relative to the line.
    line_relative_begin: usize,
    /// End index of Region relative to the line.
    line_relative_end: usize,

    /// Return the length of the Pointer.
    /// Asserts that Pointer.line_relative_end > Pointer.line_relative_begin.
    pub fn len(self: Self) usize {
        std.debug.assert(self.line_relative_end > self.line_relative_begin);
        return self.line_relative_end - self.line_relative_begin;
    }

    pub fn write(self: Self, w: *std.Io.Writer) !void {
        // Figure out how much room is needed for the gutter.
        // First, how many decimal digits are in the string rep of the line number?
        const line_num_digit_len = std.math.log10_int(self.line_num) + 1;
        // The gutter length should be wide enough to contain the number,
        // plus two extra whitespace bytes on each side.
        const gutter_len = line_num_digit_len + 2;

        // Header line.
        // Displays some useful information like template name, line/col numbers.
        try w.print("{d}:{d}\n", .{ self.line_num, self.line_relative_begin });

        // Empty line.
        try w.splatByteAll(SPACE, gutter_len);
        try w.print("{c}\n", .{PIPE});

        // Display the bad line.
        try w.print(" {} {c} {s}\n", .{ self.line_num, PIPE, self.line });

        // Where should the caret go?
        const caret_col = self.line_relative_begin + 1;
        // Place the caret below the beginning index of the problem.
        try w.splatByteAll(SPACE, gutter_len);
        try w.print("{c}", .{PIPE});
        try w.splatByteAll(' ', caret_col);
        try w.print("{c}\n", .{CARET});

        // Another empty line.
        try w.splatByteAll(SPACE, gutter_len);
        try w.print("{c}\n", .{PIPE});
    }
};

/// Identifies a location in source bytes.
pub const Region = struct {
    begin: usize,
    end: usize,

    /// Return the length of the Region.
    /// Asserts that Region.end > Region.begin.
    pub fn len(self: Region) usize {
        std.debug.assert(self.end > self.begin);
        return self.end - self.begin;
    }

    /// Return a Pointer for this Region.
    /// Maps the Region values to line-specific values within source bytes.
    /// Asserts that Region.end > Region.begin.
    pub fn pointer(self: Region, bytes: []const u8) Pointer {
        std.debug.assert(self.end > self.begin);
        const region_len = self.len();

        var unicode_len_so_far: usize = 0;
        var lines_iterator = std.mem.splitSequence(u8, bytes, "\n");
        var last_seen_line: []const u8 = undefined;
        var last_seen_line_num: usize = 0;

        while (lines_iterator.next()) |line| {
            last_seen_line = line;
            last_seen_line_num += 1;

            // TODO: Make this actually unicode aware.

            const new_len = unicode_len_so_far + line.len + 1;
            if (new_len > self.begin) {
                const rel_begin = self.begin - unicode_len_so_far;
                return .{
                    .line = line,
                    .line_num = last_seen_line_num,
                    .line_relative_begin = rel_begin,
                    .line_relative_end = rel_begin + region_len,
                };
            }
            unicode_len_so_far = new_len;
        }

        return .{
            .line = last_seen_line,
            .line_num = last_seen_line_num,
            .line_relative_begin = last_seen_line.len,
            .line_relative_end = last_seen_line.len + region_len,
        };
    }
};

test "pointer at index 0" {
    const bytes = "hello";
    const region = Region{ .begin = 0, .end = 2 };
    const p = region.pointer(bytes);
    try std.testing.expectEqualSlices(u8, "hello", p.line);
    try std.testing.expectEqual(1, p.line_num);
    try std.testing.expectEqual(0, p.line_relative_begin);
    try std.testing.expectEqual(2, p.line_relative_end);
}

test "pointer before newline" {
    const bytes = "abc\ndef";
    const region = Region{ .begin = 2, .end = 3 };
    const p = region.pointer(bytes);
    try std.testing.expectEqualSlices(u8, "abc", p.line);
    try std.testing.expectEqual(1, p.line_num);
    try std.testing.expectEqual(2, p.line_relative_begin);
    try std.testing.expectEqual(3, p.line_relative_end);
}

test "pointer to end of buffer" {
    const bytes = "line1\r\nline2\r\nline3";
    const region = Region{ .begin = 17, .end = 19 };
    const p = region.pointer(bytes);
    try std.testing.expectEqualSlices(u8, "line3", p.line);
    try std.testing.expectEqual(3, p.line_num);
    try std.testing.expectEqual(3, p.line_relative_begin);
    try std.testing.expectEqual(5, p.line_relative_end);
    try std.testing.expectEqualSlices(u8, p.line[p.line_relative_begin..p.line_relative_end], "e3");
}

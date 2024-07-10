const std = @import("std");

comptime {
    _ = @import("./compile/syntax.zig");
    _ = @import("./compile/lex.zig");
}

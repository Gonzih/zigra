const std = @import("std");
const testing = std.testing;
const process = std.process;
const builtin = @import("builtin");

pub fn ArgParser(comptime mock: bool) type {
    return struct {
        const InnerType = switch (mock) {
            true => process.ArgIteratorGeneral(.{}),
            false => process.ArgIterator,
        };

        pub const Self = @This();
        pub const ArgsList = std.ArrayList([]const u8);

        inner: InnerType,
        args: ArgsList,

        pub fn parse(allocator: std.mem.Allocator, command: []const u8) !Self {
            std.debug.print("=> Command: \"{s}\"\n", .{command});
            var iter = switch (mock) {
                true => try InnerType.init(allocator, command),
                false => try InnerType.initWithAllocator(allocator),
            };
            defer iter.deinit();
            // _ = iter.skip();

            var list = ArgsList.init(allocator);

            while (iter.next()) |arg| {
                std.debug.print("=> Arg: \"{s}\"\n", .{arg});
                try list.append(arg);
            }

            return Self{
                .inner = iter,
                .args = list,
            };
        }
    };
}

test "test real args" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(false).parse(allocator, "binary-path test");
    try testing.expect(parser.args.items.len == 1);
}

test "test mock args len" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test");
    try testing.expect(parser.args.items.len == 2);
}

test "ArgParser" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test");

    for (parser.args.items) |arg| {
        std.debug.print("=> Argument: \"{s}\"\n", .{arg});
    }

    var asserts = [_][]const u8{
        "binary-path",
        "test",
    };

    for (parser.args.items) |arg, idx| {
        const assert = asserts[idx];
        std.debug.print("=> Comparing: {s} == {s}\n", .{ arg, assert });
        try testing.expect(std.mem.eql(u8, arg, assert));
    }
}

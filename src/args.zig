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
            var iter = switch (mock) {
                true => try InnerType.init(allocator, command),
                false => try InnerType.initWithAllocator(allocator),
            };
            defer iter.deinit();
            // _ = iter.skip();

            var list = ArgsList.init(allocator);

            while (iter.next()) |arg| {
                try list.append(arg);
            }

            return Self{
                .inner = iter,
                .args = list,
            };
        }
    };
}

test "ArgParser" {
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test");

    for (parser.args.items) |arg| {
        std.debug.print("\n=> Argument: {s}\n", .{arg});
    }

    var el = parser.args.pop();
    std.debug.print("\n=> EL: {s}\n", .{el});
    try testing.expect(std.mem.eql(u8, el, "test"));
}

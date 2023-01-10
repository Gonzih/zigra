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
        pub const ArgsMap = std.StringHashMap([]const u8);

        inner: InnerType,
        args: ArgsList,
        map: ArgsMap,

        pub fn parse(allocator: std.mem.Allocator, command: []const u8) !Self {
            // std.debug.print("=> Command: \"{s}\"\n", .{command});
            var iter = switch (mock) {
                true => try InnerType.init(allocator, command),
                false => try InnerType.initWithAllocator(allocator),
            };
            // _ = iter.skip();

            var list = ArgsList.init(allocator);
            var map = ArgsMap.init(allocator);

            // If argument is a flag, add it to the map
            // split on '='
            // If argument is a value, add it to the list
            while (iter.next()) |arg| {
                if (arg[0] == '-') {
                    var split = std.mem.split(u8, arg, "=");
                    const key = split.next().?;
                    const value = if (split.next()) |v| v else "";
                    std.debug.print("=> Flag: \"{s}\" = \"{s}\"\n", .{ key, value });
                    try map.put(key, value);
                } else {
                    std.debug.print("=> Value: \"{s}\"\n", .{arg});
                    try list.append(arg);
                }
            }

            return Self{
                .inner = iter,
                .args = list,
                .map = map,
            };
        }

        pub fn getArg(self: *Self, k: []const u8) ?[]const u8 {
            return self.map.get(k);
        }

        pub fn deinit(self: *Self) void {
            self.args.deinit();
            self.map.deinit();
            self.inner.deinit();
        }
    };
}

test "test real args" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(false).parse(allocator, "binary-path test");
    defer parser.deinit();
    try testing.expect(parser.args.items.len == 1);
}

test "test mock args len" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test");
    defer parser.deinit();
    try testing.expect(parser.args.items.len == 2);
}

test "check if elements are present" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test");
    defer parser.deinit();

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

test "check if elements are present" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var parser = try ArgParser(true).parse(allocator, "binary-path test --bool-arg --string-arg=string-value");
    defer parser.deinit();

    var asserts = [_][]const u8{
        "binary-path",
        "test",
    };

    for (asserts) |assert, idx| {
        const value = parser.args.items[idx];
        std.debug.print("=> Comparing: {s} == {s}\n", .{ value, assert });
        try testing.expect(std.mem.eql(u8, value, assert));
    }

    var map_asserts = std.StringHashMap([]const u8).init(allocator);
    map_asserts.put("--bool-arg", "") catch unreachable;
    map_asserts.put("--string-arg", "string-value") catch unreachable;
    defer map_asserts.deinit();

    var it = map_asserts.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        std.debug.print("=> Found: {s} => {s}\n", .{ key, value });
        const map_value = parser.map.get(key) orelse unreachable;
        std.debug.print("=> Comparing: \"{s}\" == \"{s}\"\n", .{ map_value, value });
        try testing.expect(std.mem.eql(u8, map_value, value));
    }
}

const std = @import("std");
const testing = std.testing;
const process = std.process;
const builtin = @import("builtin");
const args = @import("args.zig");

pub fn Binding(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: *T = undefined,

        pub fn set(self: *Self, value: []const u8) !void {
            switch (@typeInfo(T)) {
                .Bool => {
                    self.ptr.* = value != "false";
                },
                .Int => {
                    const int_value = try std.fmt.parseInt(T, value, 10);
                    self.ptr.* = int_value;
                },
                .Float => {
                    const float_value = try std.fmt.parseFloat(T, value, 10);
                    self.ptr.* = float_value;
                },
                else => @compileError("Unsupported type"),
            }
        }
    };
}

fn ContextBase(comptime Parser: type) type {
    return struct {
        pub const Self = @This();

        cmd: []const u8,
        allocator: std.mem.Allocator,
        parser: *Parser,

        pub fn bind(self: *Self, comptime T: type, ptr: *T, k: []const u8) !void {
            const v = self.parser.getArg(k) orelse return;
            var binding = Binding(T){ .ptr = ptr };
            try binding.set(v);
        }
    };
}

fn CommandBase(comptime Parser: type, comptime Runner: type) type {
    return struct {
        pub const Self = @This();
        pub const InnerContext = ContextBase(Parser);

        parser: Parser,
        runner: Runner,
        cmd: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, cmd: []const u8) !Self {
            return initMock(allocator, cmd, "");
        }

        fn initMock(allocator: std.mem.Allocator, cmd: []const u8, mock_args: []const u8) !Self {
            var parser = try Parser.parse(allocator, mock_args);

            var ctx = InnerContext{
                .cmd = cmd,
                .allocator = allocator,
                .parser = &parser,
            };

            var runner = try Runner.init(ctx);

            return Self{
                .parser = parser,
                .runner = runner,
                .cmd = cmd,
                .allocator = allocator,
            };
        }

        pub fn exec(self: *Self) !void {
            var ctx = InnerContext{
                .cmd = self.cmd,
                .allocator = self.allocator,
                .parser = &self.parser,
            };

            try self.runner.run(ctx);
        }

        pub fn deinit(self: *Self) void {
            self.parser.deinit();
            self.runner.deinit();
        }
    };
}

pub const Context = ContextBase(args.ArgParser(false));
pub fn Command(comptime Runner: type) type {
    return CommandBase(args.ArgParser(false), Runner);
}

const ContextT = ContextBase(args.ArgParser(true));
fn CommandT(comptime Runner: type) type {
    return CommandBase(args.ArgParser(true), Runner);
}

test "simple test" {
    const Runner = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(ctx: ContextT) !Self {
            _ = ctx;
            return Self{};
        }

        pub fn run(self: *Self, ctx: ContextT) !void {
            _ = ctx;
            self.v = 10;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    var cmd = try CommandT(Runner).initMock(std.testing.allocator, "one", "one -v=10");
    cmd.exec() catch unreachable;
    defer cmd.deinit();

    try testing.expect(cmd.runner.v == 10);
}

test "test key binding" {
    const Runner = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(ctx: ContextT) !Self {
            var self = Self{};
            try ctx.bind(usize, &self.v, "v");

            return self;
        }

        pub fn run(self: *Self, ctx: ContextT) !void {
            _ = ctx;
            _ = self;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    var cmd = try CommandT(Runner).initMock(std.testing.allocator, "one", "one -v=20");
    cmd.exec() catch unreachable;
    defer cmd.deinit();

    try testing.expect(cmd.runner.v == 20);
}

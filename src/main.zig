const std = @import("std");
const testing = std.testing;
const process = std.process;
const builtin = @import("builtin");
const args = @import("args.zig");

pub const Context = struct {
    cmd: []const u8,
    allocator: std.mem.Allocator,
};

fn CommandBase(comptime Parser: type, comptime Runner: type) type {
    return struct {
        pub const Self = @This();

        parser: Parser,
        runner: Runner,
        cmd: []const u8,

        pub fn init(allocator: std.mem.Allocator, cmd: []const u8) Self {
            var ctx = Context{
                .cmd = cmd,
                .allocator = allocator,
            };

            return Self{
                .parser = Parser.parse(allocator, ""),
                .runner = Runner.init(ctx),
                .cmd = cmd,
            };
        }

        fn initMock(allocator: std.mem.Allocator, cmd: []const u8, mock_args: []const u8) !Self {
            var ctx = Context{
                .cmd = cmd,
                .allocator = allocator,
            };

            return Self{
                .parser = try Parser.parse(allocator, mock_args),
                .runner = Runner.init(ctx),
                .cmd = cmd,
            };
        }

        pub fn exec(self: *Self, allocator: std.mem.Allocator) !void {
            std.debug.print("args: {any}\n", .{self.parser});
            var ctx = Context{
                .cmd = self.cmd,
                .allocator = allocator,
            };

            try self.runner.run(ctx);
        }

        pub fn deinit(self: *Self) void {
            self.parser.deinit();
            self.runner.deinit();
        }
    };
}

pub fn Command(comptime Runner: type) type {
    return CommandBase(args.ArgParser(false), Runner);
}

fn CommandT(comptime Runner: type) type {
    return CommandBase(args.ArgParser(true), Runner);
}

const RunnerTone = struct {
    v: usize = 0,

    pub fn init(ctx: Context) RunnerTone {
        _ = ctx;
        return RunnerTone{};
    }

    pub fn run(self: *RunnerTone, ctx: Context) !void {
        _ = ctx;
        self.v = 10;
        return;
    }

    pub fn deinit(self: *RunnerTone) void {
        self.v = 0;
    }
};

test "test one" {
    const CommandTone = CommandT(RunnerTone);
    var cmd = try CommandTone.initMock(std.testing.allocator, "one", "one -v=10");
    cmd.exec(std.testing.allocator) catch unreachable;
    defer cmd.deinit();

    try testing.expect(cmd.runner.v == 10);
}

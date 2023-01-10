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
                    self.ptr.* = try std.fmt.parseInt(T, value, 10);
                },
                .Float => {
                    self.ptr.* = try std.fmt.parseFloat(T, value, 10);
                },
                .Enum => {
                    if (std.meta.stringToEnum(T, value)) |v| {
                        self.ptr.* = v;
                    }
                },
                .Pointer => |info| {
                    if (info.child == u8) {
                        self.ptr.* = value;
                    } else @compileError("Unsupported slice type");
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

        pub fn bind(self: *Self, comptime T: type, ptr: *T, long: []const u8, short: []const u8) !void {
            var binding = Binding(T){ .ptr = ptr };

            const short_full = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "-", short });
            defer self.allocator.free(short_full);
            if (self.parser.getArg(short_full)) |v| {
                try binding.set(v);
            }

            const long_full = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "--", long });
            defer self.allocator.free(long_full);
            if (self.parser.getArg(long_full)) |v| {
                try binding.set(v);
            }
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
        children: []*Self,
        level: usize = 0,

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

            var runner = try Runner.init(&ctx);

            return Self{
                .parser = parser,
                .runner = runner,
                .cmd = cmd,
                .allocator = allocator,
                .children = try allocator.alloc(*Self, 0),
            };
        }

        fn next(self: *Self) []const u8 {
            for (self.children) |child| {
                _ = child.next();
            }

            return self.parser.next();
        }

        pub fn exec(self: *Self) !void {
            const current_command = self.next();
            const is_current = std.mem.eql(u8, current_command, self.cmd);
            const arg_len = self.parser.args.items.len;

            std.debug.print("exec: {s} current {s} is_current: {} level: {} children.len: {}\n", .{
                self.cmd,
                current_command,
                is_current,
                self.level,
                self.children.len,
            });

            if (arg_len == 1 and self.level == 0) {
                try self._exec();
                return;
            }

            if (arg_len > 1 and arg_len > self.level + 1 and is_current) {
                for (self.children) |child| {
                    try child.exec();
                }
                return;
            }

            if (arg_len > 1 and arg_len == self.level + 1 and is_current) {
                try self._exec();
                return;
            }
        }

        fn _exec(self: *Self) !void {
            var ctx = InnerContext{
                .cmd = self.cmd,
                .allocator = self.allocator,
                .parser = &self.parser,
            };

            try self.runner.run(&ctx);
        }

        pub fn addSubcommand(self: *Self, sub: *Self) !void {
            sub.level = self.level + 1;

            self.children = try self.allocator.realloc(self.children, self.children.len + 1);
            self.children[self.children.len - 1] = sub;
        }

        pub fn deinit(self: *Self) void {
            self.parser.deinit();
            self.runner.deinit();

            for (self.children) |child| {
                std.debug.print("deinit child {s}\n", .{child.cmd});
                child.deinit();
            }

            if (self.children.len > 0) {
                self.allocator.free(self.children);
            }
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

        pub fn init(ctx: *ContextT) !Self {
            _ = ctx;
            return Self{};
        }

        pub fn run(self: *Self, ctx: *ContextT) !void {
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
    const Enum = enum {
        A,
        B,
        C,
    };

    const Runner = struct {
        v: usize = 0,
        a: usize = 0,
        en: Enum = .A,
        str: []const u8 = "",

        pub const Self = @This();

        pub fn init(ctx: *ContextT) !Self {
            var self = Self{};
            try ctx.bind(usize, &self.v, "verbose", "v");
            try ctx.bind(usize, &self.a, "another", "a");
            try ctx.bind(Enum, &self.en, "enum", "e");
            try ctx.bind([]const u8, &self.str, "string", "s");

            return self;
        }

        pub fn run(self: *Self, ctx: *ContextT) !void {
            _ = ctx;
            _ = self;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
            self.a = 0;
        }
    };

    var cmd = try CommandT(Runner).initMock(std.testing.allocator, "one", "one -v=20 --another=30 --enum=B --string=mystring");
    cmd.exec() catch unreachable;
    defer cmd.deinit();

    try testing.expect(cmd.runner.v == 20);
    try testing.expect(cmd.runner.a == 30);
    try testing.expect(cmd.runner.en == Enum.B);
    try testing.expect(std.mem.eql(u8, cmd.runner.str, "mystring"));
}

test "subcommand testing" {
    const Runner = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(ctx: *ContextT) !Self {
            _ = ctx;
            return Self{};
        }

        pub fn run(self: *Self, ctx: *ContextT) !void {
            _ = ctx;
            self.v = 10;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one two --arg=1 --beta=2";

    var cmd = try CommandT(Runner).initMock(alloc, "one", cli_args);
    defer cmd.deinit();

    var twoCmd = try CommandT(Runner).initMock(alloc, "two", cli_args);
    var threeCmd = try CommandT(Runner).initMock(alloc, "three", cli_args);
    var fourCmd = try CommandT(Runner).initMock(alloc, "four", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try threeCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(cmd.runner.v == 0);
    try testing.expect(twoCmd.runner.v == 10);
    try testing.expect(threeCmd.runner.v == 0);
    try testing.expect(fourCmd.runner.v == 0);
}

test "subcommand testing 3 levels nesting" {
    const Runner = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(ctx: *ContextT) !Self {
            _ = ctx;
            return Self{};
        }

        pub fn run(self: *Self, ctx: *ContextT) !void {
            _ = ctx;
            self.v = 69;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one two four --arg=1 --beta=2";

    var cmd = try CommandT(Runner).initMock(alloc, "one", cli_args);
    defer cmd.deinit();

    var twoCmd = try CommandT(Runner).initMock(alloc, "two", cli_args);
    var threeCmd = try CommandT(Runner).initMock(alloc, "three", cli_args);
    var fourCmd = try CommandT(Runner).initMock(alloc, "four", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try twoCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(cmd.runner.v == 0);
    try testing.expect(twoCmd.runner.v == 0);
    try testing.expect(threeCmd.runner.v == 0);
    try testing.expect(fourCmd.runner.v == 69);
}

test "subcommand testing 3 levels no match" {
    const Runner = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(ctx: *ContextT) !Self {
            _ = ctx;
            return Self{};
        }

        pub fn run(self: *Self, ctx: *ContextT) !void {
            _ = ctx;
            self.v = 69;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one three four --arg=1 --beta=2";

    var cmd = try CommandT(Runner).initMock(alloc, "one", cli_args);
    defer cmd.deinit();

    var twoCmd = try CommandT(Runner).initMock(alloc, "two", cli_args);
    var threeCmd = try CommandT(Runner).initMock(alloc, "three", cli_args);
    var fourCmd = try CommandT(Runner).initMock(alloc, "four", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try twoCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(cmd.runner.v == 0);
    try testing.expect(twoCmd.runner.v == 0);
    try testing.expect(threeCmd.runner.v == 0);
    try testing.expect(fourCmd.runner.v == 0);
}

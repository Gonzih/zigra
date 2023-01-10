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
        root: bool = true,

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

        pub fn exec(self: *Self) !void {
            const currentCommand = self.parser.next();
            const isCurrent = std.mem.eql(u8, currentCommand, self.cmd);

            if (self.parser.args.items.len == 1 and self.root) {
                try self._exec();
                return;
            }

            if (self.parser.args.items.len > 1 and self.root) {
                for (self.children) |child| {
                    try child.exec();
                }
                return;
            }

            if (self.parser.args.items.len > 1 and !self.root and isCurrent) {
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
            sub.root = false;
            sub.parser.deinit();
            sub.parser = self.parser;
            self.children = try self.allocator.realloc(self.children, self.children.len + 1);
            self.children[self.children.len - 1] = sub;
        }

        pub fn deinit(self: *Self) void {
            if (self.root) {
                self.parser.deinit();
            }

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

    var cmd = try CommandT(Runner).initMock(std.testing.allocator, "one", "one two");
    defer cmd.deinit();
    var twoCmd = try CommandT(Runner).initMock(std.testing.allocator, "two", "");
    var threeCmd = try CommandT(Runner).initMock(std.testing.allocator, "three", "");
    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    cmd.exec() catch unreachable;

    try testing.expect(cmd.runner.v == 0);
    try testing.expect(twoCmd.runner.v == 0);
}

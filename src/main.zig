const std = @import("std");
const testing = std.testing;
const process = std.process;
const assert = std.debug.assert;
const builtin = @import("builtin");
const args = @import("args.zig");

pub const Runner = struct {
    const Self = @This();

    const VTable = struct {
        init: *const fn (*anyopaque, *Context) void,
        run: *const fn (*anyopaque, *Context) void,
        deinit: *const fn (*anyopaque) void,
    };

    vtable: *const VTable,
    ptr: *anyopaque,

    fn make(pointer: anytype) Self {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);
        const alignment = @typeInfo(Ptr).Pointer.alignment;

        assert(alignment >= 1);
        assert(ptr_info == .Pointer);
        assert(@typeInfo(ptr_info.Pointer.child) == .Struct);
        assert(ptr_info.Pointer.size == .One);

        const gen = struct {
            fn initImpl(ptr: *anyopaque, ctx: *Context) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                @call(.{ .modifier = .always_inline }, std.meta.Child(Ptr).init, .{ self, ctx }) catch |e| {
                    std.debug.print("Error in init impl call: {any}", .{e});
                };
            }

            fn runImpl(ptr: *anyopaque, ctx: *Context) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                @call(.{ .modifier = .always_inline }, std.meta.Child(Ptr).run, .{ self, ctx }) catch |e| {
                    std.debug.print("Error in run impl call: {any}", .{e});
                };
            }

            fn deinitImpl(ptr: *anyopaque) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                @call(.{ .modifier = .always_inline }, std.meta.Child(Ptr).deinit, .{self});
            }

            const vtable = VTable{
                .init = initImpl,
                .run = runImpl,
                .deinit = deinitImpl,
            };
        };

        return .{
            .ptr = pointer,
            .vtable = &gen.vtable,
        };
    }

    fn init(self: *Self, ctx: *Context) void {
        self.vtable.init(self.ptr, ctx);
    }

    fn run(self: *Self, ctx: *Context) void {
        self.vtable.run(self.ptr, ctx);
    }

    fn deinit(self: *Self) void {
        self.vtable.deinit(self.ptr);
    }
};

pub fn Binding(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: *T = undefined,

        pub fn set(self: *Self, value: []const u8) !void {
            switch (@typeInfo(T)) {
                .Bool => {
                    self.ptr.* = std.mem.eql(u8, value, "false");
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

        pub fn typeString(self: *Self) []const u8 {
            _ = self;
            switch (@typeInfo(T)) {
                .Bool => return "true or false",
                .Int => return "integer",
                .Float => return "float",
                .Enum => return "enum",
                .Pointer => |info| {
                    if (info.child == u8) {
                        return "string";
                    } else @compileError("Unsupported slice type");
                },
                else => @compileError("Unsupported type"),
            }
        }
    };
}

const ArgDescriptions = std.ArrayList([]const u8);

pub const Context = struct {
    pub const Self = @This();

    cmd: []const u8,
    allocator: std.mem.Allocator,
    parser: *args.ArgParser,
    descriptions: *ArgDescriptions,

    pub fn bind(self: *Self, comptime T: type, ptr: *T, long: []const u8, short: []const u8, desc: []const u8) !void {
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

        const desc_full = try std.fmt.allocPrint(self.allocator, "--{s}, -{s} ({s}): {s}", .{ long, short, binding.typeString(), desc });
        try self.descriptions.append(desc_full);
    }
};

pub const Command = struct {
    pub const Self = @This();

    parser: args.ArgParser,
    runner: *Runner,
    cmd: []const u8,
    desc: []const u8,
    allocator: std.mem.Allocator,
    children: []*Self,
    level: usize = 0,
    descriptions: ArgDescriptions,

    pub fn init(allocator: std.mem.Allocator, rnr: *Runner, cmd: []const u8, desc: []const u8) !Self {
        return initMock(allocator, rnr, cmd, desc, "");
    }

    fn initMock(allocator: std.mem.Allocator, rnr: *Runner, cmd: []const u8, desc: []const u8, mock_args: []const u8) !Self {
        var descriptions = ArgDescriptions.init(allocator);
        var parser = try args.ArgParser.parse(allocator, mock_args);

        var ctx = Context{
            .cmd = cmd,
            .allocator = allocator,
            .parser = &parser,
            .descriptions = &descriptions,
        };

        rnr.init(&ctx);

        return Self{
            .parser = parser,
            .runner = rnr,
            .cmd = cmd,
            .desc = desc,
            .allocator = allocator,
            .children = try allocator.alloc(*Self, 0),
            .descriptions = descriptions,
        };
    }

    fn next(self: *Self) []const u8 {
        for (self.children) |child| {
            _ = child.next();
        }

        return self.parser.next();
    }

    pub fn exec(self: *Self) !void {
        var help = self.parser.getArg("--help");
        if (help == null) help = self.parser.getArg("-h");
        if (help) |_| {
            try self.printHelp();
            return;
        }

        const current_command = self.next();
        const is_current = std.mem.eql(u8, current_command, self.cmd);
        const arg_len = self.parser.args.items.len;

        if (arg_len == 1 and self.level == 0) {
            try self._exec();
            return;
        }

        if (arg_len > 1 and arg_len > self.level + 1 and (is_current or self.level == 0)) {
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
        var ctx = Context{
            .cmd = self.cmd,
            .allocator = self.allocator,
            .parser = &self.parser,
            .descriptions = &self.descriptions,
        };

        self.runner.run(&ctx);
    }

    fn printHelp(self: *Self) !void {
        try self.printCommands();
        try self.printArguments();
        std.debug.print("\n", .{});
    }

    fn printCommands(self: *Self) !void {
        if (self.level == 0) {
            var help = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ self.cmd, self.desc });
            defer self.allocator.free(help);
            std.debug.print("\n{s}\n", .{help});
            if (self.children.len > 0) {
                std.debug.print("\n\tCommands:\n", .{});
            }
        } else {
            var help = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ self.cmd, self.desc });
            defer self.allocator.free(help);
            var i: usize = 0;
            while (i < self.level) {
                std.debug.print("\t", .{});
                i += 1;
            }
            std.debug.print("\t{s}\n", .{help});
        }

        for (self.children) |child| {
            try child.printCommands();
        }

        return;
    }

    fn printArguments(self: *Self) !void {
        if (self.level == 0) {
            if (self.descriptions.items.len > 0) {
                std.debug.print("\n\tArguments:\n", .{});
            }
        }

        for (self.descriptions.items) |desc| {
            std.debug.print("\t\t{s}\n", .{desc});
        }

        for (self.children) |child| {
            try child.printArguments();
        }

        return;
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
            child.deinit();
        }

        if (self.children.len > 0) {
            self.allocator.free(self.children);
        }

        for (self.descriptions.items) |desc| {
            self.allocator.free(desc);
        }

        self.descriptions.deinit();
    }
};

test "runner wrapper" {
    const Runner1 = struct {
        pub const Self = @This();
        a: usize = 0,

        pub fn init(self: *Self, _: *Context) !void {
            self.a = 1;
        }

        pub fn run(self: *Self, _: *Context) !void {
            self.a = 2;
        }

        pub fn deinit(self: *Self) void {
            self.a = 3;
        }
    };

    const allocator = testing.allocator;

    var descriptions = ArgDescriptions.init(allocator);
    defer descriptions.deinit();
    var parser = try args.ArgParser.parse(allocator, "one two");
    defer parser.deinit();

    var ctx = Context{
        .cmd = "dummy",
        .allocator = allocator,
        .parser = &parser,
        .descriptions = &descriptions,
    };

    var r = Runner1{};
    var r1 = Runner.make(&r);
    try testing.expect(r.a == 0);
    r1.init(&ctx);
    try testing.expect(r.a == 1);
}

test "simple test" {
    const Runner1 = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(_: *Self, _: *Context) !void {}

        pub fn run(self: *Self, ctx: *Context) !void {
            _ = ctx;
            self.v = 10;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    var r = Runner1{};
    var rn = Runner.make(&r);
    var cmd = try Command.initMock(std.testing.allocator, &rn, "one", "My App", "one -v=10");
    cmd.exec() catch unreachable;
    defer cmd.deinit();

    try testing.expect(r.v == 10);
}

test "test key binding" {
    const Enum = enum {
        A,
        B,
        C,
    };

    const Runner1 = struct {
        v: usize = 0,
        a: usize = 0,
        en: Enum = .A,
        str: []const u8 = "",

        pub const Self = @This();

        pub fn init(self: *Self, ctx: *Context) !void {
            try ctx.bind(usize, &self.v, "verbose", "v", "Verbose output");
            try ctx.bind(usize, &self.a, "another", "a", "Another value");
            try ctx.bind(Enum, &self.en, "enum", "e", "Enum input");
            try ctx.bind([]const u8, &self.str, "string", "s", "String input");
        }

        pub fn run(self: *Self, ctx: *Context) !void {
            _ = ctx;
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
            self.a = 0;
        }
    };

    var r = Runner1{};
    var rn = Runner.make(&r);
    var cmd = try Command.initMock(std.testing.allocator, &rn, "one", "My App", "one -v=20 --another=30 --enum=B --string=mystring");
    cmd.exec() catch unreachable;
    defer cmd.deinit();

    try testing.expect(r.v == 20);
    try testing.expect(r.a == 30);
    try testing.expect(r.en == Enum.B);
    try testing.expect(std.mem.eql(u8, r.str, "mystring"));
}

test "subcommand testing" {
    const Runner1 = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(_: *Self, _: *Context) !void {}

        pub fn run(self: *Self, _: *Context) !void {
            self.v = 1;
        }

        pub fn deinit(_: *Self) void {}
    };

    const alloc = std.testing.allocator;
    const cli_args = "one two";

    var r1 = Runner1{};
    var rn1 = Runner.make(&r1);
    var cmd = try Command.initMock(alloc, &rn1, "app", "My App", cli_args);
    defer cmd.deinit();

    var r2 = Runner1{};
    var rn2 = Runner.make(&r2);
    var twoCmd = try Command.initMock(alloc, &rn2, "two", "Second subcommand", cli_args);

    try cmd.addSubcommand(&twoCmd);

    cmd.exec() catch unreachable;

    try testing.expect(r1.v == 0);
    try testing.expect(r2.v == 1);
}

test "subcommand testing 3 levels nesting" {
    const Runner1 = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(_: *Self, _: *Context) !void {}

        pub fn run(self: *Self, _: *Context) !void {
            self.v = 1;
        }

        pub fn deinit(_: *Self) void {}
    };

    const alloc = std.testing.allocator;
    const cli_args = "one two four";

    var r1 = Runner1{};
    var rn1 = Runner.make(&r1);
    var cmd = try Command.initMock(alloc, &rn1, "app", "My App", cli_args);
    defer cmd.deinit();

    var r2 = Runner1{};
    var rn2 = Runner.make(&r2);
    var twoCmd = try Command.initMock(alloc, &rn2, "two", "Second subcommand", cli_args);

    var r3 = Runner1{};
    var rn3 = Runner.make(&r3);
    var threeCmd = try Command.initMock(alloc, &rn3, "three", "Third subcommand", cli_args);

    var r4 = Runner1{};
    var rn4 = Runner.make(&r4);
    var fourCmd = try Command.initMock(alloc, &rn4, "four", "Fourth subcommand", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try twoCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(r1.v == 0);
    try testing.expect(r2.v == 0);
    try testing.expect(r3.v == 0);
    try testing.expect(r4.v == 1);
}

test "subcommand testing 3 levels no match" {
    const Runner1 = struct {
        v: usize = 0,

        pub const Self = @This();

        pub fn init(self: *Self, ctx: *Context) !void {
            try ctx.bind(usize, &self.v, "verbose", "v", "Verbose output");
        }

        pub fn run(self: *Self, ctx: *Context) !void {
            _ = ctx;
            self.v = 1;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one three four";

    var r1 = Runner1{};
    var rn1 = Runner.make(&r1);
    var cmd = try Command.initMock(alloc, &rn1, "app", "My App", cli_args);
    defer cmd.deinit();

    var r2 = Runner1{};
    var rn2 = Runner.make(&r2);
    var twoCmd = try Command.initMock(alloc, &rn2, "two", "Second subcommand", cli_args);

    var r3 = Runner1{};
    var rn3 = Runner.make(&r3);
    var threeCmd = try Command.initMock(alloc, &rn3, "three", "Third subcommand", cli_args);

    var r4 = Runner1{};
    var rn4 = Runner.make(&r4);
    var fourCmd = try Command.initMock(alloc, &rn4, "four", "Fourth subcommand", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try twoCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(r1.v == 0);
    try testing.expect(r2.v == 0);
    try testing.expect(r3.v == 0);
    try testing.expect(r4.v == 0);
}

test "print help" {
    const Enum = enum {
        A,
        B,
        C,
    };

    const Runner1 = struct {
        v: usize = 0,
        a: usize = 0,
        en: Enum = .A,
        str: []const u8 = "",
        b: bool = false,

        pub const Self = @This();

        pub fn init(self: *Self, ctx: *Context) !void {
            try ctx.bind(usize, &self.v, "verbose", "v", "Verbose output");
            try ctx.bind(usize, &self.a, "another", "a", "Another value");
            try ctx.bind(Enum, &self.en, "enum", "e", "Enum input");
            try ctx.bind([]const u8, &self.str, "string", "s", "String input");
            try ctx.bind(bool, &self.b, "bool", "b", "Boolean flag");
        }

        pub fn run(self: *Self, ctx: *Context) !void {
            _ = ctx;
            self.v = 0;
            return;
        }

        pub fn deinit(self: *Self) void {
            self.v = 0;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one three four --help";

    var r1 = Runner1{};
    var rn1 = Runner.make(&r1);
    var cmd = try Command.initMock(alloc, &rn1, "app", "My App", cli_args);
    defer cmd.deinit();

    var r2 = Runner1{};
    var rn2 = Runner.make(&r2);
    var twoCmd = try Command.initMock(alloc, &rn2, "two", "Second subcommand", cli_args);

    var r3 = Runner1{};
    var rn3 = Runner.make(&r3);
    var threeCmd = try Command.initMock(alloc, &rn3, "three", "Third subcommand", cli_args);

    var r4 = Runner1{};
    var rn4 = Runner.make(&r4);
    var fourCmd = try Command.initMock(alloc, &rn4, "four", "Fourth subcommand", cli_args);

    try cmd.addSubcommand(&twoCmd);
    try cmd.addSubcommand(&threeCmd);
    try twoCmd.addSubcommand(&fourCmd);

    cmd.exec() catch unreachable;

    try testing.expect(r1.v == 0);
    try testing.expect(r2.v == 0);
    try testing.expect(r3.v == 0);
    try testing.expect(r4.v == 0);
}

test "multiple runners" {
    const Runner1 = struct {
        pub const Self = @This();
        v: usize = 0,

        pub fn init(self: *Self, _: *Context) !void {
            self.v = 1;
        }

        pub fn run(self: *Self, _: *Context) !void {
            self.v = 11;
        }

        pub fn deinit(self: *Self) void {
            self.v = 111;
        }
    };

    const Runner2 = struct {
        pub const Self = @This();
        v: usize = 0,

        pub fn init(self: *Self, _: *Context) !void {
            self.v = 2;
        }

        pub fn run(self: *Self, _: *Context) !void {
            self.v = 22;
        }

        pub fn deinit(self: *Self) void {
            self.v = 222;
        }
    };

    const alloc = std.testing.allocator;
    const cli_args = "one two";

    var r1 = Runner1{};
    try testing.expect(r1.v == 0);

    var rn1 = Runner.make(&r1);
    var cmd = try Command.initMock(alloc, &rn1, "app", "My App", cli_args);
    defer cmd.deinit();
    try testing.expect(r1.v == 1);

    var r2 = Runner2{};
    try testing.expect(r2.v == 0);

    var rn2 = Runner.make(&r2);
    var twoCmd = try Command.initMock(alloc, &rn2, "two", "Second subcommand", cli_args);
    try testing.expect(r2.v == 2);

    try cmd.addSubcommand(&twoCmd);

    try cmd.exec();
    try testing.expect(r1.v == 1);
    try testing.expect(r2.v == 22);
}

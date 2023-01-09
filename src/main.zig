const std = @import("std");
const testing = std.testing;
const process = std.process;
const builtin = @import("builtin");

pub const Context = struct {
    cmd: []const u8,
};

fn CommandBase(comptime t: bool) type {
    return struct {
        const InnerIt = switch (t) {
            true => process.ArgIteratorGeneral(.{}),
            false => process.ArgIterator,
        };

        it: InnerIt,
        cmd: []const u8,
        // children: []*CommandBase(t) = &[_]*CommandBase(t){},
        run: fn (ctx: *Context) void,
        // init: ?fn (ctx: *CommandBase(t)) void = undefined,
        // allocator: std.mem.Allocator = switch (t) {
        //     true => testing.allocator,
        //     false => std.heap.page_allocator,
        // },
        allocator: std.mem.Allocator = std.heap.page_allocator,

        // pub fn exec(comptime self: *CommandBase(t)) void {
        //     var args = switch (t) {
        //         true => try InnerIt.initWithAllocator(self.allocator, "dummy cli args"),
        //         false => try InnerIt.initWithAllocator(self.allocator),
        //     };
        //     // defer args.deinit();

        //     std.debug.print("args: {any}\n", .{args});

        //     // skip my own exe name
        //     // _ = args.skip();

        //     self.execWith(args);
        // }

        pub fn execWith(comptime self: *CommandBase(t), args: InnerIt) void {
            std.debug.print("args: {any}\n", .{args});
            var ctx = Context{ .cmd = self.cmd };
            self.run(&ctx);
        }

        fn deinit(comptime self: *CommandBase(t)) void {
            for (self.children) |child| {
                child.deinit();
            }
            // self.allocator.free(self);
        }
    };
}

pub const Command = CommandBase(false);

var setThis: usize = 0;

fn run(ctx: *Context) void {
    setThis = 10;
    std.debug.print("running {s}\n", .{ctx.name});
}

test "mocked out command line" {
    const CommandTestable = CommandBase(true);

    setThis = 0;

    const a = std.testing.allocator;

    var input_cmd_line = "zig add --foo bar --baz 10";
    var it = try process.ArgIteratorGeneral(.{}).init(a, input_cmd_line);
    std.debug.print("it: {any}\n", .{it});

    comptime var cmd = CommandTestable{
        .cmd = "add",
        .run = run,
        .allocator = a,
    };

    // defer cmd.deinit();

    cmd.execWith(it);

    try testing.expect(setThis == 10);
}

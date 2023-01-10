const std = @import("std");
const testing = std.testing;
const process = std.process;
const builtin = @import("builtin");
const args = @import("args.zig");

pub const Context = struct {
    cmd: []const u8,
};

fn CommandBase(comptime Parser: type) type {
    return struct {
        parser: Parser,
        cmd: []const u8,
        children: []*CommandBase(Parser) = &[_]*CommandBase(Parser){},
        run: fn (ctx: *Context) void,

        pub fn exec(comptime self: *CommandBase(Parser), allocator: std.mem.Allocator) void {
            // defer iter.deinit();

            _ = allocator;
            std.debug.print("args: {any}\n", .{self.parser});

            // skip my own exe name
            // _ = iter.skip();

            // self.execWith(iter);
        }
    };
}

pub const Command = CommandBase(args.ArgParser(false));

var setThis: usize = 0;

fn run(ctx: *Context) void {
    setThis = 10;
    std.debug.print("running {s}\n", .{ctx.name});
}

// test "simple one" {
//     const CommandT = CommandBase(false);

//     setThis = 0;

//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     // defer arena.deinit();
//     const a = arena.allocator();

//     comptime var cmd = CommandT{
//         .cmd = "add",
//         .run = run,
//     };

//     // defer cmd.deinit();

//     cmd.exec(a);

//     try testing.expect(setThis == 10);
// }

// test "mocked out command line" {
//     const CommandT = CommandBase(false);

//     setThis = 0;

//     const a = std.testing.allocator;

//     // var input_cmd_line = "program add --foo bar --baz 10";
//     // var it = try process.ArgIteratorGeneral(.{}).init(a, input_cmd_line);
//     var it = try process.ArgIterator.initWithAllocator(a);
//     std.debug.print("it: {any}\n", .{it});

//     comptime var cmd = CommandT{
//         .cmd = "add",
//         .run = run,
//     };

//     // defer cmd.deinit();

//     cmd.execWith(it);

//     try testing.expect(setThis == 10);
// }

test "ekek" {
    const ParserT = args.ArgParser(true);
    const CommandT = CommandBase(ParserT);
    _ = CommandT;

    try testing.expect('2' == '2');
}

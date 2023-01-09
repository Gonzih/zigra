const std = @import("std");
const testing = std.testing;
const process = std.process;

pub const Context = struct {
    name: []const u8,
};

pub const Command = struct {
    name: []const u8,
    // children: []*Command = &[_]*Command{},
    run: fn (ctx: Context) void,

    pub fn exec(comptime self: Command) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        var arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit();

        var a = arena.allocator();
        var args = try process.argsWithAllocator(a);
        defer args.deinit();

        std.debug.print("args: {any}\n", .{args});

        // skip my own exe name
        _ = args.skip();

        self.execWith(args);
    }

    pub fn execWith(comptime self: Command, args: process.ArgIterator) void {
        std.debug.print("args: {any}\n", .{args});
        self.run(Context{ .name = self.name });
    }
};

fn run(ctx: Context) void {
    std.debug.print("running {s}\n", .{ctx.name});
}

test "basic command functionality" {
    const cmd = Command{
        .name = "add",
        .run = run,
    };

    cmd.exec();

    try testing.expect(11 == 10);
}

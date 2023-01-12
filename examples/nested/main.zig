const std = @import("std");
const zigra = @import("zigra");

const Enum = enum {
    Extract,
    Transform,
    Load,
};

const Handler = struct {
    pub const Self = @This();
    v: usize = 0,

    pub fn init(_: *Self, _: *zigra.Context) !void {}

    pub fn run(_: *Self, ctx: *zigra.Context) !void {
        std.debug.print("runner {s}\n", .{ctx.cmd});
    }

    pub fn deinit(_: *Self) void {}
};

const SubHandler = struct {
    pub const Self = @This();
    v: usize = 0,

    pub fn init(_: *Self, _: *zigra.Context) !void {}

    pub fn run(_: *Self, ctx: *zigra.Context) !void {
        std.debug.print("sub runner {s}\n", .{ctx.cmd});
    }

    pub fn deinit(_: *Self) void {}
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var h1 = Handler{};
    var r1 = zigra.Runner.make(&h1);
    var root = try zigra.Command.init(alloc, &r1, "app", "First subcommand");
    defer root.deinit();

    var h2 = SubHandler{};
    var r2 = zigra.Runner.make(&h2);
    var one = try zigra.Command.init(alloc, &r2, "one", "Second subcommand");

    try root.addSubcommand(&one);

    try root.exec();
}

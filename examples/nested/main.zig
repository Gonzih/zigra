const std = @import("std");
const zigra = @import("zigra");

const Enum = enum {
    Extract,
    Transform,
    Load,
};

const SubRunner = struct {
    pub const Self = @This();

    pub fn init(_: *zigra.Context) !Self {
        return Self{};
    }

    pub fn run(_: *Self, ctx: *zigra.Context) !void {
        std.debug.print("sub runner {s}\n", .{ctx.cmd});
    }

    pub fn deinit(_: *Self) void {}
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var root = try zigra.Command(SubRunner).init(alloc, "hello", "My Hello World App");
    defer root.deinit();

    var one = try zigra.Command(SubRunner).init(alloc, "one", "First subcommand");
    var two = try zigra.Command(SubRunner).init(alloc, "two", "Second subcommand");
    var three = try zigra.Command(SubRunner).init(alloc, "three", "Third subcommand");
    var four = try zigra.Command(SubRunner).init(alloc, "four", "Fourth subcommand");

    try one.addSubcommand(&three);
    try two.addSubcommand(&four);

    try root.addSubcommand(&one);
    try root.addSubcommand(&two);

    try root.exec();
}

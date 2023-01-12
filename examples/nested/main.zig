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

    verbose: bool = false,
    threads: usize = 0,
    kind: Enum = .Extract,
    id: []const u8 = "",

    pub fn init(self: *Self, ctx: *zigra.Context) !void {
        try ctx.bind(bool, &self.verbose, "verbose", "v", "Verbose output");
        try ctx.bind(usize, &self.threads, "threads", "t", "Number of threads to run");
        try ctx.bind(Enum, &self.kind, "worker-kind", "w", "Which worker to run");
        try ctx.bind([]const u8, &self.id, "uuid", "u", "Unique identifier for the worker");
    }

    pub fn run(self: *Self, ctx: *zigra.Context) !void {
        std.debug.print("cmd: {s}\n verbose: {}\n threads: {}\n kind: {any}\n id: {s}\n", .{
            ctx.cmd,
            self.verbose,
            self.threads,
            self.kind,
            self.id,
        });
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

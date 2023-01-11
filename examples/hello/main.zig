const std = @import("std");
const zigra = @import("zigra");

const Enum = enum {
    Extract,
    Transform,
    Load,
};

const Runner = struct {
    verbose: bool = false,
    threads: usize = 0,
    kind: Enum = .Extract,
    id: []const u8 = "",

    pub const Self = @This();

    pub fn init(ctx: *zigra.Context) !Self {
        var self = Self{};
        try ctx.bind(bool, &self.verbose, "verbose", "v", "Verbose output");
        try ctx.bind(usize, &self.threads, "threads", "t", "Number of threads to run");
        try ctx.bind(Enum, &self.kind, "worker-kind", "w", "Which worker to run");
        try ctx.bind([]const u8, &self.id, "uuid", "u", "Unique identifier for the worker");

        return self;
    }

    pub fn run(self: *Self, _: *zigra.Context) !void {
        std.debug.print("verbose: {}\n threads: {}\n kind: {any}\n id: {s}\n", .{
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
    var cmd = try zigra.Command(Runner).init(alloc, "hello", "My Hello World App");
    defer cmd.deinit();
    try cmd.exec();
}

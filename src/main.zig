const std = @import("std");
const config = @import("config");
const noe = @import("noe");

/// Failure while processing the process's arguements.
const ArgumentError = error{
    UnrecognisedOption,
    TooManyArguments,
};

const Command = enum {
    version,
    run,
};

/// Print the binary's version to stdout.
fn version(init: std.process.Init) std.Io.Writer.Error!void {
    var buf: [1024]u8 = undefined;
    var w = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &w.interface;
    try stdout.print("noe {s}", .{config.version});
    try stdout.flush();
}

pub const panic = noe.panic;
/// Load arguments, initialize, and run the editor.
pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    defer args.deinit();

    _ = args.skip();
    const arg1 = args.next() orelse "run";
    const arg2 = args.next();

    const command = std.meta.stringToEnum(Command, arg1) orelse {
        return try noe.run(init, arg2);
    };
    switch (command) {
        .version => if (arg2) |_| return ArgumentError.TooManyArguments else try version(init),
        .run => try noe.run(init, arg2),
    }
}

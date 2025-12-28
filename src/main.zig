const std = @import("std");
const config = @import("config");
const noe = @import("noe");

/// Failure while processing the process's arguements.
const ArgumentError = error{
    UnrecognisedOption,
    TooManyArguments,
};

/// Print the binary's version to stdout.
fn version() std.io.Writer.Error!void {
    var buf: [1024]u8 = undefined;
    var w = std.fs.File.stdout().writer(&buf);
    const stdout = &w.interface;
    try stdout.print("noe {s}", .{config.version});
    try stdout.flush();
}

/// Load arguments, initialize, and run the editor.
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();
    if (args.next()) |arg1| {
        if (std.mem.eql(u8, arg1, "--version")) {
            if (args.skip()) {
                return ArgumentError.TooManyArguments;
            }
            try version();
        } else {
            try noe.run(arg1);
        }
    } else {
        try noe.run(null);
    }
}

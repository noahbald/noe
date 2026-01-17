const std = @import("std");

const Editor = @import("../editor.zig");

const Error = error{QuitFailed};

/// The list of editor commands that require no arguments.
///
/// These commands can be assigned to keys or typed.
pub const Static = union(enum) {
    CursorLeft,
    CursorDown,
    CursorUp,
    CursorRight,
    PageUp,
    PageDown,
    GotoLineStart,
    GotoLineEnd,
    Quit,
    Noop,

    pub fn call(self: Static, editor: *Editor) Error!void {
        return switch (self) {
            .CursorLeft => cursorLeft(editor),
            .CursorDown => cursorDown(editor),
            .CursorUp => cursorUp(editor),
            .CursorRight => cursorRight(editor),
            .PageUp => pageUp(editor),
            .PageDown => pageDown(editor),
            .GotoLineStart => gotoLineStart(editor),
            .GotoLineEnd => gotoLineEnd(editor),
            .Quit => quit(editor),
            .Noop => noop(editor),
        };
    }
};

fn cursorLeft(editor: *Editor) void {
    editor.cx = std.math.sub(u16, editor.cx, 1) catch 0;
}
fn cursorDown(editor: *Editor) void {
    editor.cy = @min(editor.cy + 1, editor.private.term.height());
}
fn cursorUp(editor: *Editor) void {
    editor.cy = std.math.sub(u16, editor.cy, 1) catch 0;
}
fn cursorRight(editor: *Editor) void {
    editor.cx = @min(editor.cx + 1, editor.private.term.width());
}
fn pageUp(editor: *Editor) void {
    editor.cy = std.math.sub(u16, editor.cy, editor.private.term.height()) catch 0;
}
fn pageDown(editor: *Editor) void {
    editor.cy = @min(editor.cy + editor.private.term.height(), editor.private.term.height());
}
fn gotoLineStart(editor: *Editor) void {
    editor.cx = 0;
}
fn gotoLineEnd(editor: *Editor) void {
    editor.cx = editor.private.term.width();
}
fn quit(editor: *Editor) Error!void {
    editor.private.term.deinit() catch {
        return Error.QuitFailed;
    };
    std.process.exit(0);
}
fn noop(_: *Editor) void {}

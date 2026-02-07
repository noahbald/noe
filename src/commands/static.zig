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
    NextWordStart,
    PrevWordStart,
    NextWordEnd,
    NextLongWordStart,
    PrevLongWordStart,
    NextLongWordEnd,
    PageUp,
    PageDown,
    GotoLineStart,
    GotoLineEnd,
    Quit,
    QuitForce,
    Noop,

    pub fn call(self: Static, editor: *Editor) Error!void {
        return switch (self) {
            .CursorLeft => cursorLeft(editor),
            .CursorDown => cursorDown(editor),
            .CursorUp => cursorUp(editor),
            .CursorRight => cursorRight(editor),
            .NextWordStart => nextWordStart(editor),
            .PrevWordStart => prevWordStart(editor),
            .NextWordEnd => nextWordEnd(editor),
            .NextLongWordStart => nextLongWordStart(editor),
            .PrevLongWordStart => prevLongWordStart(editor),
            .NextLongWordEnd => nextLongWordEnd(editor),
            .PageUp => pageUp(editor),
            .PageDown => pageDown(editor),
            .GotoLineStart => gotoLineStart(editor),
            .GotoLineEnd => gotoLineEnd(editor),
            .Quit => quit(editor),
            .QuitForce => quitForce(editor),
            .Noop => noop(editor),
        };
    }
};

fn cursorLeft(editor: *Editor) void {
    editor.private.window.?.cursorLeft();
}
fn cursorDown(editor: *Editor) void {
    editor.private.window.?.cursorDown();
}
fn cursorUp(editor: *Editor) void {
    editor.private.window.?.cursorUp();
}
fn cursorRight(editor: *Editor) void {
    editor.private.window.?.cursorRight();
}
fn nextWordStart(editor: *Editor) void {
    editor.private.window.?.nextWordStart(false);
}
fn prevWordStart(editor: *Editor) void {
    editor.private.window.?.prevWordStart(false);
}
fn nextWordEnd(editor: *Editor) void {
    editor.private.window.?.nextWordEnd(false);
}
fn nextLongWordStart(editor: *Editor) void {
    editor.private.window.?.nextWordStart(true);
}
fn prevLongWordStart(editor: *Editor) void {
    editor.private.window.?.prevWordStart(true);
}
fn nextLongWordEnd(editor: *Editor) void {
    editor.private.window.?.nextWordEnd(true);
}
fn pageUp(editor: *Editor) void {
    editor.private.window.?.pageUp(editor.private.term.height());
}
fn pageDown(editor: *Editor) void {
    editor.private.window.?.pageDown(editor.private.term.height());
}
fn gotoLineStart(editor: *Editor) void {
    editor.private.window.?.gotoLineStart();
}
fn gotoLineEnd(editor: *Editor) void {
    editor.private.window.?.gotoLineEnd();
}
fn quit(editor: *Editor) Error!void {
    // TODO: Check unsaved files
    return quitForce(editor);
}
fn quitForce(editor: *Editor) Error!void {
    editor.private.term.deinit() catch {
        return Error.QuitFailed;
    };
    std.process.exit(0);
}
fn noop(_: *Editor) void {}

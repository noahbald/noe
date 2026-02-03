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

// TODO: calls to rebalanceScroll should dynamically consider the window's rendered position
const WINDOW_PADDING = 2;

fn cursorLeft(editor: *Editor) void {
    editor.private.window.?.cursorLeft();
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn cursorDown(editor: *Editor) void {
    editor.private.window.?.cursorDown();
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn cursorUp(editor: *Editor) void {
    editor.private.window.?.cursorUp();
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn cursorRight(editor: *Editor) void {
    editor.private.window.?.cursorRight();
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn pageUp(editor: *Editor) void {
    editor.private.window.?.pageUp(editor.private.term.height());
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn pageDown(editor: *Editor) void {
    editor.private.window.?.pageDown(editor.private.term.height());
    editor.private.window.?.rebalanceScroll(editor.private.term.height() - WINDOW_PADDING);
}
fn gotoLineStart(editor: *Editor) void {
    editor.private.window.?.gotoLineStart();
}
fn gotoLineEnd(editor: *Editor) void {
    editor.private.window.?.gotoLineEnd();
}
fn quit(editor: *Editor) Error!void {
    editor.private.term.deinit() catch {
        return Error.QuitFailed;
    };
    std.process.exit(0);
}
fn noop(_: *Editor) void {}

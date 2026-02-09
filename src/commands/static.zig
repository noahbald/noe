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
    FindTillNextChar,
    FindNextChar,
    FindTillPrevChar,
    FindPrevChar,
    GotoLine: usize,
    PageUp,
    PageDown,
    GotoLineStart,
    GotoLineEnd,
    Quit,
    QuitForce,
    Noop,

    pub fn call(self: Static, editor: *Editor) Error!void {
        if (self.empend()) {
            editor.mode = .{ .Pending = self };
        }
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
            else => noop(editor),
        };
    }

    pub fn empend(self: Static) bool {
        return switch (self) {
            .FindTillNextChar, .FindNextChar, .FindTillPrevChar, .FindPrevChar, .GotoLine => true,
            else => false,
        };
    }

    pub fn settlePending(self: Static, editor: *Editor, char: u8) Error!void {
        return switch (self) {
            .FindTillNextChar => findTillNextChar(editor, char),
            .FindNextChar => findNextChar(editor, char),
            .FindTillPrevChar => findTillPrevChar(editor, char),
            .FindPrevChar => findPrevChar(editor, char),
            .GotoLine => |line| {
                if (char == '\r' or char == '\n') {
                    gotoLine(editor, line -| 1);
                } else if (std.ascii.isDigit(char)) {
                    editor.mode = .{ .Pending = .{ .GotoLine = (line * 10) + (char - '0') } };
                }
            },
            else => noop(editor),
        };
    }

    pub fn format(self: Static, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try switch (self) {
            .CursorLeft => writer.write("CursorLeft"),
            .CursorDown => writer.write("CursorDown"),
            .CursorUp => writer.write("CursorUp"),
            .CursorRight => writer.write("CursorRight"),
            .NextWordStart => writer.write("NextWordStart"),
            .PrevWordStart => writer.write("PrevWordStart"),
            .NextWordEnd => writer.write("NextWordEnd"),
            .NextLongWordStart => writer.write("NextLongWordStart"),
            .PrevLongWordStart => writer.write("PrevLongWordStart"),
            .NextLongWordEnd => writer.write("NextLongWordEnd"),
            .FindTillNextChar => writer.write("FindTillNextChar"),
            .FindNextChar => writer.write("FindNextChar"),
            .FindTillPrevChar => writer.write("FindTillPrevChar"),
            .FindPrevChar => writer.write("FindPrevChar"),
            .GotoLine => |line| return writer.print("GotoLine({d})", .{line}),
            .PageUp => writer.write("PageUp"),
            .PageDown => writer.write("PageDown"),
            .GotoLineStart => writer.write("GotoLineStart"),
            .GotoLineEnd => writer.write("GotoLineEnd"),
            .Quit => writer.write("Quit"),
            .QuitForce => writer.write("QuitForce"),
            .Noop => writer.write("Noop"),
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
fn findTillNextChar(editor: *Editor, char: u8) void {
    editor.private.window.?.findChar(false, true, char);
}
fn findNextChar(editor: *Editor, char: u8) void {
    editor.private.window.?.findChar(false, false, char);
}
fn findTillPrevChar(editor: *Editor, char: u8) void {
    editor.private.window.?.findChar(true, true, char);
}
fn findPrevChar(editor: *Editor, char: u8) void {
    editor.private.window.?.findChar(true, false, char);
}
fn gotoLine(editor: *Editor, line: usize) void {
    editor.private.window.?.gotoLine(line);
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

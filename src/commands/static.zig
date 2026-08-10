const std = @import("std");

const Editor = @import("../editor.zig");

const Error = error{ QuitFailed, EditFailed };

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
    InsertMode,
    AppendMode,
    InsertAtLineStart,
    InsertAtLineEnd,
    OpenBelow,
    OpenAbove,
    NormalMode,
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
            .InsertMode => insertMode(editor),
            .NormalMode => normalMode(editor),
            .AppendMode => appendMode(editor),
            .InsertAtLineStart => insertAtLineStart(editor),
            .InsertAtLineEnd => insertAtLineEnd(editor),
            .OpenBelow => openBelow(editor),
            .OpenAbove => openAbove(editor),
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
            .InsertMode => writer.write("InsertMode"),
            .AppendMode => writer.write("AppendMode"),
            .InsertAtLineStart => writer.write("InsertAtLineStart"),
            .InsertAtLineEnd => writer.write("InsertAtLineEnd"),
            .OpenBelow => writer.write("OpenBelow"),
            .OpenAbove => writer.write("OpenAbove"),
            .NormalMode => writer.write("NormalMode"),
            .Quit => writer.write("Quit"),
            .QuitForce => writer.write("QuitForce"),
            .Noop => writer.write("Noop"),
        };
    }
};

fn cursorLeft(editor: *Editor) void {
    if (editor.private.window) |window| window.cursorLeft();
}
fn cursorDown(editor: *Editor) void {
    if (editor.private.window) |window| window.cursorDown();
}
fn cursorUp(editor: *Editor) void {
    if (editor.private.window) |window| window.cursorUp();
}
fn cursorRight(editor: *Editor) void {
    if (editor.private.window) |window| window.cursorRight();
}
fn nextWordStart(editor: *Editor) void {
    if (editor.private.window) |window| window.nextWordStart(false);
}
fn prevWordStart(editor: *Editor) void {
    if (editor.private.window) |window| window.prevWordStart(false);
}
fn nextWordEnd(editor: *Editor) void {
    if (editor.private.window) |window| window.nextWordEnd(false);
}
fn nextLongWordStart(editor: *Editor) void {
    if (editor.private.window) |window| window.nextWordStart(true);
}
fn prevLongWordStart(editor: *Editor) void {
    if (editor.private.window) |window| window.prevWordStart(true);
}
fn nextLongWordEnd(editor: *Editor) void {
    if (editor.private.window) |window| window.nextWordEnd(true);
}
fn findTillNextChar(editor: *Editor, char: u8) void {
    if (editor.private.window) |window| window.findChar(false, true, char);
}
fn findNextChar(editor: *Editor, char: u8) void {
    if (editor.private.window) |window| window.findChar(false, false, char);
}
fn findTillPrevChar(editor: *Editor, char: u8) void {
    if (editor.private.window) |window| window.findChar(true, true, char);
}
fn findPrevChar(editor: *Editor, char: u8) void {
    if (editor.private.window) |window| window.findChar(true, false, char);
}
fn gotoLine(editor: *Editor, line: usize) void {
    if (editor.private.window) |window| window.gotoLine(line);
}
fn pageUp(editor: *Editor) void {
    if (editor.private.window) |window| window.pageUp(editor.private.term.height());
}
fn pageDown(editor: *Editor) void {
    if (editor.private.window) |window| window.pageDown(editor.private.term.height());
}
fn gotoLineStart(editor: *Editor) void {
    if (editor.private.window) |window| window.gotoLineStart();
}
fn gotoLineEnd(editor: *Editor) void {
    if (editor.private.window) |window| window.gotoLineEnd();
}
fn insertMode(editor: *Editor) void {
    editor.mode = .Insert;
}
fn normalMode(editor: *Editor) void {
    editor.mode = .Normal;
}
fn appendMode(editor: *Editor) void {
    cursorRight(editor);
    normalMode(editor);
}
fn insertAtLineStart(editor: *Editor) void {
    gotoLineStart(editor);
    insertMode(editor);
}
fn insertAtLineEnd(editor: *Editor) void {
    gotoLineEnd(editor);
    insertMode(editor);
}
fn openAbove(editor: *Editor) Error!void {
    if (editor.private.window) |window| {
        cursorUp(editor);
        gotoLineEnd(editor);
        window.insert('\n') catch return Error.EditFailed;
        insertMode(editor);
    }
}
fn openBelow(editor: *Editor) Error!void {
    if (editor.private.window) |window| {
        gotoLineEnd(editor);
        window.insert('\n') catch return Error.EditFailed;
        insertMode(editor);
    }
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

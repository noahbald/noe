# Noah's Ordinary Editor

Noe is a terminal editor inspired by Kilo and Kibi; 1024 LOC terminals.

A text editor with modern features; configurable by modification and extensible by invocation.

## Features

- [x] UTF-8 Support
- [x] Portable across Windows, POSIX, and WASI platforms
- [ ] Helix inspired controls and commands
- Modern and simple internals
  - [x] Written in Zig
  - [x] Rope for text processing
  - [ ] Tree-sitter integration
  - [ ] LSP support
  - [x] Zero dependencies

## Prior Art

Noe may borrow code and concepts from these open-source projects

- [Kilo](https://viewsourcecode.org/snaptoken/kilo/index.html), a tutorial text-editor written in around 1000 LOC
- [Kibi](https://github.com/ilai-deutel/kibi), a Kilo inspired text-editor written in Rust
- [Kilo.zig](https://github.com/h4rr9/kilo.zig), a Kilo implementation in Zig
- [Helix](https://github.com/helix-editor/helix), canvas rendering, commands
- [Zed](https://zed.dev/blog/zed-decoded-rope-sumtree), with great resources on Ropes

## License

This project is licensed under GPLv3 license unless stated otherwise.

The following files and directories are licensed under MIT. Feel free to use or modify without the limits of the GPLv3 license.

- `src/rope.zig` and `src/rope/`
- `src/iter.zig` and `src/iter/`
- `src/config.zig`

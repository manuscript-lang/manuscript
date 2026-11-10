[Wiki](../index.md) › [Runtime](index.md)

# The terminal keeps Rust to raw mode, text reads and writes; decoding lives in Manuscript

Decision: `ms-std-terminal` only enters raw mode, reads UTF-8 text with a 40 or 50 ms wait, writes text, reports the size and writes a registered restore string on close (`raw.rs`, with OS calls in `sys_unix.rs` termios and `sys_windows.rs` console modes). Key and paste decoding (`TerminalDecoder`), resize detection, the lone-Escape timeout, every escape sequence and the mode switch-on and restore strings are Manuscript in `stdlib/cli/terminal.ms`. Chinmay asked for this after a first version kept the decoder in Rust.

Verified: `cli/terminal.ms` is in the `io` import cycle, so it cannot import `@std/string.ms`, `collections.ms` (`join`, `extend`), `@std/time.ms` calls or `internal/string.ms`; the checker then panics with "cyclic standard source dependency" and hides the real error, which an unknown name leaves as a hang. Build strings with `+` (`concat_all` merges pairwise) and loop instead of `extend`. To see the real diagnostic, check a user-file copy of the module against a working standard library.

On Windows a blocking `ReadFile` on the console hangs on a resize or focus record: read `ReadConsoleInputW` only when `GetNumberOfConsoleInputEvents` is nonzero and keep the key characters (virtual-terminal input makes them the same escape bytes Unix delivers). Raw mode switches on bracketed paste, modifyOtherKeys and the kitty keyboard flag so Shift-Enter and pastes decode; the restore string undoes them and shows the cursor.

Apply when: adding a terminal feature (mouse, focus, another key protocol) or a platform.
Evidence: [terminal.ms](../../stdlib/cli/terminal.ms), [raw](../../crates/ms-std-terminal/src/raw.rs), [decoder test](../../tests/e2e/testdata/stdlib/terminal_decoder.ms), [pty test](../../crates/ms-cli/tests/terminal.rs).
Verify: `cargo test -p ms-std-terminal`, `cargo check -p ms-std-terminal --target x86_64-pc-windows-msvc`, the decoder e2e test, and Windows and macOS CI dispatched on the branch.

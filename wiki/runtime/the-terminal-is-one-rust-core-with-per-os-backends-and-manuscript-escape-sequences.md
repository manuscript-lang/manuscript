[Wiki](../index.md) › [Runtime](index.md)

# The terminal's C core is libuv's uv_tty; decoding lives in Manuscript

Decision: `src/runtime/std/terminal.c` only enters raw mode, reads UTF-8 text with a 40 ms wait, writes text, reports the size and writes a registered restore string on close. It is `uv_tty` on every platform (raw mode, size, console writes); each raw terminal has one private libuv loop that runs on a pool thread for the length of one wait, watching the tty, SIGWINCH, a quick timer and an async wake-up. `uv_tty_init` dup2s a reopened, non-blocking description over fd 0 and 1, so the terminal puts the descriptors' modes back when it is destroyed. Key and paste decoding (`TerminalDecoder`), resize detection, the lone-Escape timeout, every escape sequence and the mode switch-on and restore strings are Manuscript in `src/stdlib/cli/terminal.ms`. Chinmay asked for this after a first version kept the decoder in Rust.

Verified: `cli/terminal.ms` is in the `io` import cycle, so it cannot import `@std/string.ms`, `collections.ms` (`join`, `extend`), `@std/time.ms` calls or `internal/string.ms`; the checker then panics with "cyclic standard source dependency" and hides the real error, which an unknown name leaves as a hang. Build strings with `+` (`concat_all` merges pairwise) and loop instead of `extend`. To see the real diagnostic, check a user-file copy of the module against a working standard library.

The Windows console path is libuv's (it reads key records as virtual-terminal bytes and signals SIGWINCH on resize), not hand-written. Raw mode switches on bracketed paste, modifyOtherKeys and the kitty keyboard flag so Shift-Enter and pastes decode; the restore string undoes them and shows the cursor.

A read whose caller gave up (a timed-out `next`) leaves its pool job running until the wake-up reaches it, and under CPU load that job can read the next key into a wait nobody collects. Read jobs therefore hold `read_lock` for their whole run, and an abandoned job gets no buffer (`UV_ENOBUFS`), so the bytes stay in the descriptor for the next wait. The pty test lost a key about 1 run in 12 under 24 parallel copies before this; it passes 72 of 72 now.

Apply when: adding a terminal feature (mouse, focus, another key protocol) or a platform.
Evidence: [terminal.ms](../../src/stdlib/cli/terminal.ms), [terminal.c](../../src/runtime/std/terminal.c), [decoder test](../../tests/conformance/fixtures/e2e/stdlib/terminal_decoder.ms), [pty test](../../crates/ms-cli/tests/terminal.rs).
Verify: `make c-test` (`std_terminal`), `cargo test -p ms-cli --test terminal` (pty), the decoder e2e test, and Windows and macOS CI dispatched on the branch.

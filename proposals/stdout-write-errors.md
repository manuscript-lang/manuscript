# Report failed writes to standard output

## Summary

- Problem: a compiled program whose standard output cannot take data (`>/dev/full`, a closed descriptor) sees `write` and `flush` succeed and exits 0, so output is lost silently (#3890).
- Change: the runtime remembers the first failed write to standard output. `stdout().flush()` and the next `stdout().write(..)` return that failure as an `Error`, and a program that would exit 0 exits 1 with a message on standard error. `print` keeps returning `Unit`.
- Decision requested: none; no syntax, type or signature changes (`write` and `flush` already return `Unit!`).

## Status

Implemented in this PR, 2026-11-14, checked against `bd90fccd`. Not a language change: the stream methods already declare `Unit!`.

## Problem

```manuscript
import stdout from "@std/io/io.ms"

fn main() Unit!:
    out := stdout()
    out.write("hello\n")?
    out.flush()?
```

`./prog >/dev/full` prints nothing, exits 0. Opening `/dev/full` as a file and writing to it reports "no space left on device", so standard output is the outlier. Verified: `crates/ms-rt/src/io.rs` `flush_locked` calls `sys::write_all`, which returns `()` and drops every error (`crates/ms-rt/src/sys.rs:201`, `sys_windows.rs:223`).

## Design

- `sys::write_all` returns the error code (0 for success) on Unix and Windows; callers that ignore it keep their behavior (standard error, test record files).
- `io.rs` keeps one process-wide `STDOUT_ERROR` (atomic code). `flush_locked` stores the first failure and discards the buffer it could not write, so a later flush does not retry the same bytes.
- A broken pipe (`EPIPE` on Unix, `ERROR_BROKEN_PIPE` and `ERROR_NO_DATA` on Windows) is not recorded: a program piped into `head` still ends quietly, as today.
- `msstd_io_stdout_status(flush)` (in `ms-std-io`) optionally flushes, then returns the stored failure as a status with its text, classified by `ms_std_fs::sys::classify` and described by `describe`, the same path file writes use. `StdoutText.flush`, `StdoutBytes.flush` and the `write` methods call it, so a failure shows as `error(...)` with the usual kind (`ENOSPC`, `EIO`).
- At process exit `msrt_start` flushes; if a failure was recorded and the exit status is 0, it writes `error: write to standard output: <text>` to standard error and returns 1. A nonzero status stays as it is.
- `print` and the text/bytes `write` fast path stay buffered and infallible. A program that never flushes learns of the failure at exit, which is when the buffer is written.
- Windows and macOS get the same behavior: the code comes from `GetLastError` and `errno`, with no platform-specific path.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt/src/sys.rs`, `sys_windows.rs` | `write_all` returns the code | existing runtime tests |
| `ms-rt/src/io.rs` | sticky error `stdout_error`, EPIPE excluded | `ms-cli/tests/stdout_errors.rs` |
| `ms-rt/src/start.rs` | exit status 1 with a message | `ms-cli/tests/stdout_errors.rs` (a read-only file as stdout, every platform) |
| `ms-std-io/src/lib.rs` | `msstd_io_stdout_status` | same test |
| `stdlib/io/io.ms`, `stdlib/internal/promises.ms` | stdout `write` and `flush` return the failure | same test |
| `documentation/core-language/cleanup/scopes.md` | state the rule | docs check |

## Alternatives

- Make `print` fault on failure: puts a branch and a possible unwind on the hottest output path, and `print` has no error channel by design.
- Write stdout unbuffered: reports errors at the call site but costs a system call per line (the buffer exists for that reason).
- Return the error from every `write`, not the first one: the buffered write has not reached the OS yet, so there is nothing to report until a flush.
- Do nothing: silent data loss with exit 0 in CI and shell pipelines.

## Open questions

- Should the exit message include the program name? Left plain to match other runtime errors.

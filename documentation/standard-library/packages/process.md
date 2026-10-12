+++
title = "Subprocesses and terminal I/O"
weight = 57
+++

# Subprocesses and terminal I/O

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use stream helpers for bounded reads and copies, and Commands for buffered subprocess execution. The caller supplies the streams or command service. Helpers do not acquire authority or close the streams for you.

## `@std/io.ms`

```manuscript
fn copy(input: ReadStream, output: WriteStream, max_bytes: Int) -> Result[Int, IoError]
fn read_all(input: ReadStream, max_bytes: Int) -> Result[Bytes, IoError]
fn read_line(input: ReadStream, max_bytes: Int) -> Result[Optional[String], IoError]
```

## Running commands

[Commands.run](../data-and-io/streams.md) uses explicit `process.commands` access. Supply the program, arguments, input, aggregate output bound, and timeout. It waits for execution and returns captured `exit_code`, `stdout`, and `stderr`. A nonzero exit is returned data. Running a shell must be explicit.

## Stream helpers

These helpers use shared stream views without closing them. Keep the streams' own cleanup scopes open for the whole call. All helpers cooperate with cancellation and enforce cumulative byte limits.

| Helper | Behavior |
| --- | --- |
| `copy` | Returns the number of bytes copied. An error may occur after a prefix was written; there is no rollback. |
| `read_all` | Returns all bytes only on success. |
| `read_line` | Reads one byte at a time so it does not consume the next line. It strips LF and a preceding CR, and accepts a final line without a terminator. |

`read_line` returns `none` only if EOF occurs before any data. Its positive `max_bytes` includes terminator bytes. Invalid UTF-8 returns `InvalidData`; overflow returns `LimitExceeded` and may consume a prefix plus one boundary byte. Copy and read_all allow a zero limit for an empty source.

Source streams must return nonempty chunks within the requested size. A malformed stream implementation causes `Failed`.

Expected stream failures preserve their original `IoError` case and payload. Invalid UTF-8 returns `IoError.InvalidData`; an exceeded byte bound returns `IoError.LimitExceeded`. Helpers do not flatten Result or catch cancellation and faults. Convert a File view explicitly to ReadStream when required by the contract-view rules.

Interactive subprocess handles, terminal raw mode and secret reads, REPL/history, and richer child environment or working-directory options remain future work. Buffered Commands is the current subprocess API; there is no new Process/Child hierarchy.

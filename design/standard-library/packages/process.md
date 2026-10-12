+++
title = "Subprocesses and terminal I/O"
weight = 57
+++

# Subprocesses and terminal I/O

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/io.ms`

```text
fn copy(input: ReadStream, output: WriteStream, max_bytes: Int) -> Result[Int, LibraryError]
fn read_all(input: ReadStream, max_bytes: Int) -> Result[Bytes, LibraryError]
fn read_line(input: ReadStream, max_bytes: Int) -> Result[Optional[String], LibraryError]
```

The existing [Commands.run contract](../data-and-io/streams.md) is retained: explicit `process.commands` authority, program/arguments/input, aggregate output bound, timeout, joined execution and captured exit_code/stdout/stderr. Nonzero exit is data. Shell execution must be explicit. This expansion does not introduce a conflicting Process/Child hierarchy.

Copy/read_all/read_line borrow shared stream views, never close them, cooperate with cancellation and enforce cumulative byte bounds. Copy writes a consumed prefix before an error and cannot roll it back. Read_all returns all bytes only on success. Read_line reads one byte at a time to avoid consuming the next line, strips LF and preceding CR, returns a final unterminated line, and returns none only when EOF occurs before any data. Its positive max_bytes includes terminator bytes; invalid UTF-8 returns InvalidData, overflow returns LimitExceeded. Overflow may consume a prefix and one boundary byte. Copy/read_all permit a zero bound for an empty source. Source streams must return nonempty chunks within the requested bound or helpers return Failed.

Expected underlying IoError is translated to LibraryError.Failed with a diagnostic; the helper does not flatten Result or catch cancellation/faults. Native File views can be explicitly converted to ReadStream views using existing contract conversion rules when needed. Interactive subprocess handles, terminal raw mode/secret reads, REPL/history, and richer child environment/working-directory options remain deferred; current buffered Commands provides the functional subprocess option.

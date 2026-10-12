+++
title = "Logging"
weight = 18
+++

# Logging

API reference: [log](reference/log.md).

Import `create` and a transport from `@std/log.ms`. A logger combines level filtering, structured JSON fields, and reusable context. Transports send complete records to stdout, an append-only file, or a supplied `WriteStream`. Logging failures are returned as `Result` errors.

## Write a record

This complete program writes one JSON line to stdout. `try` propagates logging failures through the standard `Error` boundary.

<!-- manuscript-example: {"mode":"run","stdout":"{\"level\":30,\"msg\":\"listening\",\"port\":8080}\n"} -->
```manuscript
import {create, stdout_transport} from "@std/log.ms"
import JsonValue from "@std/json.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"

fn announce() -> Result[Unit, Error]:
    with transport = stdout_transport():
        let logger = try create(transport: transport, timestamp: false)
        let fields = Map[String, JsonValue]().with_entry(key: "port", value: JsonValue.NumberValue(text: "8080"))
        let written = try logger.info(message: "listening", fields: fields)
        return ok(value: unit)

export fn main() -> Int:
    match announce():
        ok(_): return 0
        error(_): return 1
```

`fields` is optional; `logger.info(message: "started")` emits a message without additional fields. JSON fields support null, booleans, exact numbers, strings, arrays, and nested objects through `JsonValue`. See the [JSON reference](reference/json.md) for construction and parsing. Invalid numeric text or cyclic JSON values return `LogError.InvalidData` before the transport receives data.

Each record is compact UTF-8 JSON followed by LF. The top-level envelope contains numeric `level`, `msg`, and, by default, `time` as Unix epoch milliseconds. Additional fields appear at the top level in map insertion order. The envelope owns `level`, `msg`, and `time`; supplied bindings or fields with those keys are ignored, including `time` when timestamps are disabled. Embedded newlines and quotes are escaped, keeping one record per physical line.

## Levels and context

`trace`, `debug`, `info`, `warn`, `error`, and `fatal` return `Result[Unit, LogError]`. Their levels are 10, 20, 30, 40, 50, and 60 respectively. `log(level: level, message: message, fields: fields)` selects a method's level dynamically. `LogLevel.Silent` is a filtering threshold; using it as a record level returns `InvalidInput`. `fatal` emits a record and leaves process termination to the caller.

The default threshold is `LogLevel.Info`. Pass `level: LogLevel.Debug` to `create`, or use `logger.set_level(LogLevel.Debug)` later. `logger.level()` returns the current threshold and `logger.enabled(LogLevel.Debug)` checks whether that level passes it. `LogLevel.Silent` disables all logging. Filtered calls return `ok(unit)` without serialization or transport access, even if the transport is closed; arguments still evaluate normally.

Pass `bindings: bindings` to `create` for persistent fields. `logger.child(bindings)` makes a logger with extra context and the parent's current threshold, timestamp setting, record limit, and transport. Parent level changes do not change existing children. Bindings merge in parent → child → per-call order; later values win. Construction and child creation copy top-level map membership, preserving ordinary references to nested JSON collections. Logging does not mutate supplied maps. Synchronize externally if nested collections are modified concurrently.

## Transports and cleanup

- `stdout_transport()` borrows the host stdout stream.
- `stream_transport(output)` borrows a supplied `WriteStream`, including a source implementation for testing or integration.
- `file_transport(path)` opens or creates a file for append with mode `0600` for newly created files, subject to the host umask. It owns that file. Parent directories must already exist. Open failures return `LogError.FileSystem(cause)` with the original `FileSystemError`.

Use `with` to close transports. Loggers and their children share the transport but do not own it. Closing a borrowed transport leaves its underlying stream open; closing a file transport releases its file handle. Close is idempotent, ends admission, cancels active operations, and joins admitted calls. Later transport writes and flushes return `LogError.Closed`. Source streams must cooperate with cancellation to make interrupted operations finish.

Transports serialize complete writes and apply backpressure synchronously. They do not queue records in the background. `logger.flush()` delegates to the transport; file flush synchronizes the file to disk, while stdout uses the host stream's flush. Check flush results when persistence matters. Closing is cleanup, not an implicit successful flush. A write failure may follow a partial external write; no rollback is promised. Stream failures preserve their `IoError` as `LogError.Io(cause)`.

For file logging, replace the stdout acquisition in the example with `with transport = try file_transport("events.ndjson"):` and import `file_transport`.

A custom transport implements the ordinary `Transport` interface: `write(data: Bytes) -> Result[Unit, LogError]`, `flush() -> Result[Unit, LogError]`, and `close() -> Unit`. Construct its explicit `Transport(value: implementation)` view and pass it to `create`. Custom implementations own their synchronization and lifecycle behavior.

## Record limits

`create` accepts `max_bytes: Optional[Int] = none`. Omission or `none` imposes no record limit. A supplied nonnegative limit counts the entire UTF-8 JSON line, including LF. An exact fit succeeds. Excess returns `LimitExceeded` before writing, and a negative limit returns `InvalidInput` during creation. A zero limit rejects every enabled record. Filtering happens before the record budget is checked.

The caller chooses fields and their sensitivity; automatic redaction and object inspection are not part of this API. Bound untrusted inputs when necessary: serialization checks the supplied output budget, but the input collections and escaped string temporaries may already occupy memory.

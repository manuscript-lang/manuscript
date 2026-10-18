# async-log

A non-blocking file transport for `@std/log.ms`, written entirely in Manuscript.

`async_file_transport(path, max_bytes, max_age, max_files, queue_size)` returns a `Transport`.

- `write` queues the record on a bounded `BlockingQueue` and returns at once. A full queue (default 8192 records) returns `LogError.LimitExceeded` and drops the record. The bound is soft by the number of writers racing at the limit, because the queue keeps 4096 items of headroom so that no put ever waits. A write or rotation failure is returned by the next `write` or `flush`.
- A writer task started in a `TaskGroup` appends queued records to `path`.
- The file rotates before a record that would pass `max_bytes`, or when it is `max_age` old, counted from when the transport opened the file or the existing file's last modification. Rotated files are `path.1` (newest) through `path.N`. `max_files` counts the active file plus rotated files; older files are deleted. Omitted limits do not apply; supplied limits must be positive or the call returns `InvalidInput`.
- `flush` waits until earlier records are written and synced. `close` writes accepted records, then releases the file.

```manuscript
import {create} from "@std/log.ms"
import {async_file_transport} from "./async_file_transport.ms"

fn log_started() Result[Unit, Error]:
    with transport = try async_file_transport("app.ndjson", max_bytes: 10485760, max_files: 5):
        let logger = try create(transport: transport)
        let written = try logger.info(message: "started")
        return ok(unit)
```

Run the tests with `ms test examples/async-log/ms.toml`.

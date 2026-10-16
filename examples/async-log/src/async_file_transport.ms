import {Transport, LogError} from "@std/log.ms"
import Bytes from "@std/bytes.ms"
import {
    filesystem,
    FileSystem,
    FileHandle,
    FileInfo,
    FileSystemError
} from "@std/fs.ms"
import BlockingQueue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import {
    Duration,
    Instant,
    Timestamp,
    clock,
    wall_clock,
    duration
} from "@std/time.ms"

# A queued request for the writer task: append a record, or acknowledge once earlier records are on disk.
type Item:
    case Record(data: Bytes)
    case Flush(reply: BlockingQueue[Result[Unit, LogError]])

# Admission and failure state shared by producers, flushers, and the writer.
type Shared:
    closed: Bool
    failed: Bool
    pending: Optional[LogError]

# State owned by the writer task alone.
type Writer:
    fs: FileSystem
    path: String
    max_bytes: Optional[Int]
    max_age: Optional[Duration]
    max_files: Optional[Int]
    handle: Optional[FileHandle]
    size: Int
    opened: Instant

type AsyncFileTransport:
    queue: BlockingQueue[Item]
    capacity: Int
    shared: Synchronized[Shared]
    group: TaskGroup
    writer: Task[Unit]

fn io_error(cause: FileSystemError) -> LogError:
    return LogError.FileSystem(cause)

fn lift(result: Result[Unit, FileSystemError]) -> Result[Unit, LogError]:
    match result:
        ok(_): return ok(unit)
        error(cause): return error(io_error(cause))

fn numbered(path: String, index: Int) -> String:
    if index == 0: return path

    return "{path}.{index}"

fn exists(fs: FileSystem, path: String) -> Bool:
    match fs.stat(path: path, follow_links: false):
        ok(_): return true
        error(_): return false

fn age_of(modified: Timestamp) -> Duration:
    match wall_clock().now().difference(modified):
        ok(age): return age
        error(_): return duration(0)

# Adopts an existing file's size, and its modification time as the start of its age.
fn adopt(w: Writer, info: FileInfo) -> Unit:
    w.size = info.size

    if info.size > 0: w.opened = clock().now().shift(age_of(info.modified).negate())

# Opens the active file for append and reads its size and age.
fn open_active(w: Writer) -> Result[Unit, LogError]:
    let handle = match w.fs.open(path: w.path, flags: "a", mode: 384):
        ok(opened): opened
        error(cause): return error(io_error(cause))

    w.handle = some(handle)
    w.size = 0
    w.opened = clock().now()

    match handle.stat():
        ok(info): adopt(w, info)
        error(_): return ok(unit)

    return ok(unit)

fn close_file(w: Writer) -> Unit:
    match w.handle:
        some(handle): handle.close()
        none: return unit

    w.handle = none

# Shifts path to path.1, path.1 to path.2, and so on. Files past max_files are removed.
fn rotate(w: Writer) -> Result[Unit, LogError]:
    close_file(w)
    var last = 0

    while exists(w.fs, numbered(w.path, last + 1)):
        last = last + 1

    let keep = w.max_files.map(fn(files: Int) -> Int: files - 1).unwrap_or(last + 1)
    var drop = last

    while drop >= keep and drop > 0:
        try lift(w.fs.remove(path: numbered(w.path, drop)))
        drop = drop - 1

    var index = last

    if keep - 1 < index: index = keep - 1

    while index >= 0:
        try lift(
            (
                w
                .fs
                .rename(
                    source: numbered(w.path, index),
                    destination: numbered(w.path, (index + 1))
                )
            )
        )
        index = index - 1

    if keep == 0: try lift(w.fs.remove(path: w.path))

    return open_active(w)

fn rotation_due(w: Writer, length: Int) -> Bool:
    if w.size == 0: return false

    let over_size = (
        w
        .max_bytes
        .map(fn(limit: Int) -> Bool: w.size + length > limit)
        .unwrap_or(false)
    )
    let over_age = (
        w
        .max_age
        .map(
            fn(limit: Duration) -> Bool: (
                clock().now().difference(w.opened).compare(limit) >= 0
            )
        )
        .unwrap_or(false)
    )
    return over_size or over_age

fn active_file(w: Writer) -> Result[FileHandle, LogError]:
    match w.handle:
        some(handle): return ok(handle)
        none: return error(LogError.Closed)

fn has_file(w: Writer) -> Bool:
    match w.handle:
        some(_): return true
        none: return false

fn append(w: Writer, data: Bytes) -> Result[Unit, LogError]:
    if not has_file(w): try open_active(w)

    if rotation_due(w, data.length()): try rotate(w)

    let handle = try active_file(w)
    try lift(handle.write(data))
    w.size = w.size + data.length()
    return ok(unit)

fn sync_file(w: Writer) -> Result[Unit, LogError]:
    let handle = try active_file(w)
    return lift(handle.sync())

fn record_failure(shared: Synchronized[Shared], cause: LogError) -> Unit:
    with locked = shared.lock():
        let state = locked.get()
        if state.failed: return unit

        state.failed = true
        state.pending = some(cause)

# Returns the first failure since the last report and clears it.
fn take_failure(shared: Synchronized[Shared]) -> Optional[LogError]:
    with locked = shared.lock():
        let state = locked.get()
        let found = state.pending
        state.pending = none
        state.failed = false
        return found

fn store(w: Writer, shared: Synchronized[Shared], data: Bytes) -> Unit:
    match append(w, data):
        ok(_): return unit
        error(cause): return record_failure(shared, cause)

fn serve(w: Writer, shared: Synchronized[Shared], item: Item) -> Unit:
    match item:
        Record(data): return store(w, shared, data)
        Flush(reply):
            reply.put(sync_file(w))
            return unit

fn run(w: Writer, queue: BlockingQueue[Item], shared: Synchronized[Shared]) -> Unit:
    while true:
        match queue.take():
            some(item): serve(w, shared, item)
            none: return close_file(w)

    return unit

# Queues a record without waiting. The lock makes the length check and the put one step among producers,
# and only the writer removes items, so the put never blocks.
fn admit(t: AsyncFileTransport, data: Bytes) -> Result[Unit, LogError]:
    with locked = t.shared.lock():
        if locked.get().closed: return error(LogError.Closed)
        if t.queue.length() >= t.capacity: return error(LogError.LimitExceeded)

        t.queue.put(Item.Record(data: data))
        return ok(unit)

fn is_closed(t: AsyncFileTransport) -> Bool:
    with locked = t.shared.lock():
        return locked.get().closed

fn wait_for_writer(t: AsyncFileTransport) -> Result[Unit, LogError]:
    if is_closed(t): return error(LogError.Closed)

    let reply = BlockingQueue[Result[Unit, LogError]](1)
    if not t.queue.put(Item.Flush(reply: reply)): return error(LogError.Closed)

    match reply.take():
        some(result): return result
        none: return error(LogError.Closed)

impl Transport for AsyncFileTransport:
    fn write(data: Bytes) -> Result[Unit, LogError]:
        match take_failure(self.shared):
            some(cause): return error(cause)
            none: return admit(self, data)

    fn flush() -> Result[Unit, LogError]:
        try wait_for_writer(self)

        match take_failure(self.shared):
            some(cause): return error(cause)
            none: return ok(unit)

    fn close() -> Unit:
        with locked = self.shared.lock():
            locked.get().closed = true

        self.queue.close()
        let joined = self.writer.join()
        self.group.close()

fn not_positive(limit: Optional[Int]) -> Bool:
    return limit.map(fn(value: Int) -> Bool: value <= 0).unwrap_or(false)

fn age_not_positive(limit: Optional[Duration]) -> Bool:
    return (
        limit
        .map(fn(value: Duration) -> Bool: value.compare(duration(0)) <= 0)
        .unwrap_or(false)
    )

# Appends log records to a file without blocking the logger.
export fn async_file_transport(
    path: String,
    max_bytes: Optional[Int] = none,
    max_age: Optional[Duration] = none,
    max_files: Optional[Int] = none,
    queue_size: Optional[Int] = none
) -> Result[Transport, LogError]:
    if not_positive(max_bytes) or not_positive(max_files) or not_positive(queue_size): return error(
        LogError.InvalidInput
    )
    if age_not_positive(max_age): return error(LogError.InvalidInput)

    let w = Writer(
        fs: filesystem(),
        path: path,
        max_bytes: max_bytes,
        max_age: max_age,
        max_files: max_files,
        handle: none,
        size: 0,
        opened: clock().now()
    )
    try open_active(w)
    let capacity = queue_size.unwrap_or(8192)
    let queue = BlockingQueue[Item](capacity)
    let shared = Synchronized[Shared](
        Shared(closed: false, failed: false, pending: none)
    )
    let group = TaskGroup()
    let writer = group.start(fn() -> Unit: run(w, queue, shared))
    return ok(
        Transport(
            value: AsyncFileTransport(
                queue: queue,
                capacity: capacity,
                shared: shared,
                group: group,
                writer: writer
            )
        )
    )

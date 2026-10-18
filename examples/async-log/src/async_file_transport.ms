import {Transport, LogError} from "@std/log.ms"
import Bytes from "@std/bytes.ms"
import {filesystem, FileSystem, FileHandle, FileInfo, FileSystemError} from "@std/fs.ms"
import BlockingQueue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import {Duration, Instant, Timestamp, clock, wall_clock, duration} from "@std/time.ms"

# A queued request for the writer task: append a record, or acknowledge once earlier records are on disk.
type Item:
    case Record(data: Bytes)
    case Flush(reply: BlockingQueue[Result[Unit, LogError]])

# State owned by the writer task alone.
type Writer:
    fs: FileSystem
    path: String
    # Zero means no limit.
    max_bytes: Int
    max_age_ns: Int
    max_files: Int
    handle: Optional[FileHandle]
    size: Int
    opened: Instant

type AsyncFileTransport:
    queue: BlockingQueue[Item]
    capacity: Int
    # The writer's first unreported failure; the writer is its only producer.
    failures: BlockingQueue[LogError]
    # Serializes the rare take of a reported failure.
    failure_lock: Synchronized[Unit]
    group: TaskGroup
    writer: Task[Unit]

fn io_error(cause: FileSystemError) LogError:
    return LogError.FileSystem(cause)

fn lift[T](result: Result[T, FileSystemError]) Result[T, LogError]:
    if let value = result: return ok(value)

    return result.err() | io_error | error

fn numbered(path: String, index: Int) String:
    if index == 0: return path

    return "{path}.{index}"

fn exists(fs: FileSystem, path: String) Bool:
    return fs.stat(path, follow_links: false).is_ok()

fn age_of(modified: Timestamp) Duration:
    return wall_clock().now().difference(modified).get(duration(0))

# Adopts an existing file's size, and its modification time as the start of its age.
fn adopt(w: Writer, info: FileInfo) Unit:
    w.size = info.size
    if info.size > 0: w.opened = clock().now().shift(age_of(info.modified).negate())

# Opens the active file for append and reads its size and age.
fn open_active(w: Writer) Result[Unit, LogError]:
    let handle = w.fs.open(w.path, "a", 384) | try lift
    w.handle = some(handle)
    w.size = 0
    w.opened = clock().now()
    if let info = handle.stat(): adopt(w, info)
    return ok(unit)

fn close_file(w: Writer) Unit:
    if let handle = w.handle: handle.close()
    w.handle = none

# Shifts path to path.1, path.1 to path.2, and so on. Files past max_files are removed.
fn rotate(w: Writer) Result[Unit, LogError]:
    close_file(w)
    var last = 0
    while exists(w.fs, numbered(w.path, last + 1)):
        last += 1
    var keep = last + 1
    if w.max_files > 0: keep = w.max_files - 1
    var drop = last

    while drop >= keep and drop > 0:
        w.fs.remove(numbered(w.path, drop)) | try lift
        drop -= 1

    var index = last
    if keep - 1 < index: index = keep - 1

    while index >= 0:
        let source = numbered(w.path, index)
        let destination = numbered(w.path, index + 1)
        w.fs.rename(source, destination) | try lift
        index -= 1

    if keep == 0: w.fs.remove(w.path) | try lift
    return open_active(w)

fn rotation_due(w: Writer, length: Int) Bool:
    if w.size == 0: return false
    if w.max_bytes > 0 and w.size + length > w.max_bytes: return true
    if w.max_age_ns > 0: return (
        clock().now().difference(w.opened).to_nanoseconds() >= w.max_age_ns
    )

    return false

fn active_file(w: Writer) Result[FileHandle, LogError]:
    if let handle = w.handle: return ok(handle)

    return error(LogError.Closed)

fn has_file(w: Writer) Bool:
    if let _handle = w.handle: return true

    return false

fn append(w: Writer, data: Bytes) Result[Unit, LogError]:
    if not has_file(w): try open_active(w)
    if rotation_due(w, data.length()): try rotate(w)
    let handle = try active_file(w)
    handle.write(data) | try lift
    w.size += data.length()
    return ok(unit)

fn sync_file(w: Writer) Result[Unit, LogError]:
    return try active_file(w) | .sync() | lift

# Keeps the first failure until a producer reports it.
fn record_failure(failures: BlockingQueue[LogError], cause: LogError) Unit:
    if failures.length() == 0: failures.put(cause)

# Returns the failure the writer reported since the last call, if any. The unlocked length check keeps
# the common case lock-free; the lock keeps two producers from both waiting in take for one failure.
fn take_failure(
    failures: BlockingQueue[LogError],
    failure_lock: Synchronized[Unit]
) Optional[LogError]:
    if failures.length() == 0: return none

    with locked = failure_lock.lock():
        if failures.length() == 0: return none

        return failures.take()

fn store(w: Writer, failures: BlockingQueue[LogError], data: Bytes) Unit:
    let appended = append(w, data)
    if appended.is_error(): return record_failure(failures, appended.err())

    return unit

fn serve(w: Writer, failures: BlockingQueue[LogError], item: Item) Unit:
    match item:
        Record(data): return store(w, failures, data)
        Flush(reply):
            reply.put(sync_file(w))
            return unit

fn run(w: Writer, queue: BlockingQueue[Item], failures: BlockingQueue[LogError]) Unit:
    while true:
        if let item = queue.take():
            serve(w, failures, item)
        else:
            return close_file(w)

# Queues a record without waiting. The queue holds 4096 items of headroom beyond `capacity`, so a put never waits
# even when concurrent producers pass the length check together; only the writer removes items.
fn admit(t: AsyncFileTransport, data: Bytes) Result[Unit, LogError]:
    if t.queue.length() >= t.capacity: return error(LogError.LimitExceeded)
    if not t.queue.put(Item.Record(data)): return error(LogError.Closed)

    return ok(unit)

fn wait_for_writer(t: AsyncFileTransport) Result[Unit, LogError]:
    let reply = BlockingQueue[Result[Unit, LogError]](1)
    if not t.queue.put(Item.Flush(reply)): return error(LogError.Closed)
    if let result = reply.take(): return result

    return error(LogError.Closed)

impl Transport for AsyncFileTransport:
    fn write(data: Bytes) Result[Unit, LogError]:
        if let cause = take_failure(self.failures, self.failure_lock): return error(
            cause
        )

        return admit(self, data)

    fn flush() Result[Unit, LogError]:
        try wait_for_writer(self)
        if let cause = take_failure(self.failures, self.failure_lock): return error(
            cause
        )

        return ok(unit)

    fn close() Unit:
        self.queue.close()
        let _ignored = self.writer.join()
        self.group.close()

fn not_positive(limit: Optional[Int]) Bool:
    return limit.map(fn(value: Int) Bool: value <= 0).get(false)

fn age_not_positive(limit: Optional[Duration]) Bool:
    return (
        limit
        .map(fn(value: Duration) Bool: value.compare(duration(0)) <= 0)
        .get(false)
    )

# Appends log records to a file without blocking the logger.
export fn async_file_transport(
    path: String,
    max_bytes: Optional[Int] = none,
    max_age: Optional[Duration] = none,
    max_files: Optional[Int] = none,
    queue_size: Optional[Int] = none
) Result[Transport, LogError]:
    if not_positive(max_bytes) or not_positive(max_files) or not_positive(queue_size): return error(
        LogError.InvalidInput
    )
    if age_not_positive(max_age): return error(LogError.InvalidInput)

    let w = Writer(
        fs: filesystem(),
        path,
        max_bytes: max_bytes.get(0),
        max_age_ns: (
            max_age
            .map(fn(limit: Duration) Int: limit.to_nanoseconds())
            .get(0)
        ),
        max_files: max_files.get(0),
        handle: none,
        size: 0,
        opened: clock().now()
    )
    try open_active(w)
    let capacity = queue_size.get(8192)
    let queue = BlockingQueue[Item](capacity + 4096)
    let failures = BlockingQueue[LogError]()
    let group = TaskGroup()
    let writer = group.start(fn() Unit: run(w, queue, failures))
    return ok(
        Transport(
            value: AsyncFileTransport(
                queue,
                capacity,
                failures,
                failure_lock: Synchronized[Unit](unit),
                group,
                writer
            )
        )
    )

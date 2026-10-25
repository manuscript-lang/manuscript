from "@std/archive.ms" import compress_writer, CompressionFormat
from "@std/io.ms" import WriteStream, IoError
from "@std/bytes.ms" import Bytes
from "@std/shared.ms" import Shared, share
from "@std/testing.ms" import expect_equal, expect_true

type Sink:
    bytes: Shared[Bytes]
    fail: Bool = False

impl WriteStream for Sink:
    var def close() -> Unit: return ()

    var def flush() -> Result[Unit, IoError]: return ok(())

    var def write(data: String) -> Result[Unit, IoError]: return self.write_bytes(
        data.to_bytes()
    )

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        if self.fail: return error(IoError.Unavailable)

        let old = self.bytes.take()
        self.bytes.put(old.concat(data))
        return ok(())

test "compression writers round trip all formats across writes and sync flush":
    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let bytes = share("".to_bytes())
        var writer = try compress_writer(Sink(bytes), format)
        try writer.write("first")
        try writer.flush()
        try expect_true(bytes.get().length() > 0)
        try writer.write("second")
        try writer.finish()
        try expect_equal(
            (
                try format.decompress(bytes.get().clone())
            ).decode_utf8().get(),
            "firstsecond"
        )
        try expect_equal(writer.write("late").err(), IoError.Closed)
        try expect_equal(writer.finish().err(), IoError.Closed)

test "compression limits and downstream errors poison retained aliases without finalizing":
    let bytes = share("".to_bytes())
    var writer = try compress_writer(Sink(bytes), max_input_bytes: 3)
    var alias = writer.clone()
    try expect_equal(writer.write("four").err(), IoError.LimitExceeded)
    try expect_equal(alias.write("x").err(), IoError.Closed)
    try expect_equal(bytes.get().length(), 0)

    var bounded = try compress_writer(Sink(bytes), max_output_bytes: 0)
    try expect_equal(bounded.write("x").err(), IoError.LimitExceeded)
    try expect_equal(bounded.finish().err(), IoError.Closed)

    var failing = try compress_writer(Sink(bytes, True))
    try expect_equal(failing.write("x").err(), IoError.Unavailable)
    try expect_equal(failing.finish().err(), IoError.Closed)

test "closing abandons compression and invalidates all aliases":
    let bytes = share("".to_bytes())
    var writer = try compress_writer(Sink(bytes))
    var alias = writer.clone()
    try writer.write("partial")
    writer.close()
    try expect_equal(alias.finish().err(), IoError.Closed)
    try expect_true(CompressionFormat.Gzip.decompress(bytes.get().clone()).is_error())

from "@std/tasks.ms" import TaskGroup, TaskError
from "@std/time.ms" import sleep

type SlowSink:
    touched: Shared[Bool]

impl WriteStream for SlowSink:
    var def close() -> Unit: return ()

    var def flush() -> Result[Unit, IoError]: return ok(())

    var def write(data: String) -> Result[Unit, IoError]: return self.write_bytes(
        data.to_bytes()
    )

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        self.touched.take()
        self.touched.put(True)
        sleep(2.seconds)
        return ok(())

test "cancellation during downstream suspension poisons escaped compression aliases":
    let touched = share(False)
    var writer = try compress_writer(SlowSink(touched))
    let copy = writer.clone()

    with TaskGroup[Unit]() as tasks:
        let task = tasks.spawn(
            lambda channel:
                var local = copy.clone()
                let written = local.write("pending")
            ,
            timeout: 20.milliseconds
        )

        try expect_equal(task.result().err(), TaskError.TimedOut)

    try expect_true(touched.get())
    try expect_equal(writer.write("late").err(), IoError.Closed)
    writer.close()
    try expect_equal(writer.finish().err(), IoError.Closed)

from "@std/web_multipart.ms" import multipart, MultipartPart, MultipartLimits
from "@std/http.ms" import Request, headers
from "@std/io.ms" import IoError, ReadStream, read_all
from "@std/streams.ms" import from_bytes
from "@std/shared.ms" import share, Shared
from "@std/testing.ms" import expect_equal, expect_true

def request(text: String, chunk: Int = 65536) -> Request:
    let fields = headers()
    (
        fields.append(
            "Content-Type", "multipart/form-data; boundary=example".to_bytes()
        ).get()
    )
    return Request(headers: fields, body: from_bytes(text.to_bytes(), chunk))

let upload = "--example\r\nContent-Disposition: form-data; name=first\r\n\r\none\r\n--example\r\nContent-Disposition: form-data; name=file; filename=\"a;b.txt\"\r\nContent-Type: application/octet-stream\r\n\r\ntwo\r\n--example--\r\n"

test "multipart streams split delimiters and expires retained readers":
    let names = share(List[String]())
    let bodies = share(List[String]())
    let retained = share(List[MultipartPart]())

    let visit = lambda (part: MultipartPart) -> Result[Unit, IoError]:
        var named = names.take()
        named.append(part.name.clone())
        names.put(named)

        let bytes = try read_all(part.body, some(100))
        var contents = bodies.take()
        contents.append(bytes.decode_utf8().get())
        bodies.put(contents)

        var readers = retained.take()
        readers.append(part.clone())
        retained.put(readers)
        return ok(())

    try multipart(request(upload, 1), visit)
    try expect_equal(names.get(), ["first", "file"])
    try expect_equal(bodies.get(), ["one", "two"])

    var readers = retained.take()

    for item in readers:
        var reader = item.clone()
        try expect_true(reader.body.read().is_error())

test "multipart drains skipped parts and enforces limits and complete framing":
    let ignore: Callable[[MultipartPart], Result[Unit, IoError]] = lambda part: ok(())
    try multipart(request(upload, 2), ignore)
    try expect_true(
        multipart(
            request(upload), ignore, MultipartLimits(max_part_bytes: 2)
        ).is_error()
    )
    try expect_true(
        multipart(
            request(upload), ignore, MultipartLimits(max_parts: 1)
        ).is_error()
    )
    try expect_true(
        multipart(
            request(upload), ignore, MultipartLimits(max_bytes: 10)
        ).is_error()
    )
    try expect_true(
        multipart(
            request(
                "--example\r\nContent-Disposition: form-data; name=x\r\n\r\nunfinished"
            ),
            ignore
        ).is_error()
    )

test "multipart preserves false boundary prefixes and validates dispositions":
    let body = "--example\r\nContent-Disposition: form-data; name=x\r\n\r\na\r\n--exampleXmore\r\n--example--\r\n"
    let found = share("")
    try multipart(request(body, 1), lambda part: capture(part, found))
    try expect_equal(found.get(), "a\r\n--exampleXmore")
    try expect_true(
        multipart(
            request(
                "--example\r\nContent-Disposition: form-data; name=a; name=b\r\n\r\nx\r\n--example--\r\n"
            ),
            lambda part: ok(())
        ).is_error()
    )

def capture(part: MultipartPart, found: Shared[String]) -> Result[Unit, IoError]:
    let bytes = try read_all(part.body, some(100))
    found.take()
    found.put(bytes.decode_utf8().get())
    return ok(())

from "@std/web_multipart.ms" import with_upload
from "@std/fs.ms" import filesystem, dirname
from "@std/tasks.ms" import TaskGroup, TaskError
from "@std/time.ms" import sleep

test "temporary uploads ignore client paths and clean up on success error and cancellation":
    let path = share("")

    let save = lambda (location: String) -> Result[Unit, IoError]:
        path.take()
        path.put(location.clone())
        return ok(())

    try multipart(request(upload), lambda part: with_upload(part, save))
    try expect_true(filesystem().stat(path.get(), False).is_error())
    try expect_true(filesystem().stat(dirname(path.get()), False).is_error())

    let failing = lambda (location: String) -> Result[Unit, IoError]:
        path.take()
        path.put(location.clone())
        return error(IoError.InvalidData)

    try expect_true(
        multipart(
            request(upload), lambda part: with_upload(part, failing)
        ).is_error()
    )
    try expect_true(filesystem().stat(dirname(path.get()), False).is_error())

    with TaskGroup[Unit]() as tasks:
        let task = tasks.spawn(
            lambda channel:
                let result = multipart(
                    request(upload),
                    lambda part: with_upload(
                        part,
                        lambda location:
                            path.take()
                            path.put(location.clone())
                            sleep(2.seconds)
                            return ok(())
                    )
                )
            ,
            timeout: 100.milliseconds
        )
        try expect_equal(task.result().err(), TaskError.TimedOut)

    try expect_true(filesystem().stat(dirname(path.get()), False).is_error())

test "multipart rejects invalid closing suffix ambiguous metadata and swallowed read errors":
    for data in [
        "--example\r\nContent-Disposition: form-data; name=a\r\n\r\nx\r\n--example--BAD",
        "--example\r\nContent-Disposition: form-data; name=a; name*=x\r\n\r\nx\r\n--example--\r\n",
        "--example\r\nContent-Disposition: form-data; name=a\r\nContent-Transfer-Encoding: base64\r\n\r\nx\r\n--example--\r\n",
        "--example\r\nContent-Disposition: form-data; name=a"
    ]:
        let result = multipart(request(data, 1), lambda part: ok(()))
        if result.is_ok(): panic(data)

    let ignore_error = lambda (part: MultipartPart) -> Result[Unit, IoError]:
        let ignored = read_all(part.body, some(100))
        return ok(())

    try expect_true(
        multipart(
            request(upload), ignore_error, MultipartLimits(max_part_bytes: 1)
        ).is_error()
    )

from "@std/core.ms" import panic

test "multipart parameter keys preserve extended marker":
    var values = Map[String, String]()
    values.add("name*", "x")
    try expect_true(values.contains("name*"))
    try expect_true(
        "name*=x".take("name*=x".index_of("=").get()).trim().lower() == "name*"
    )

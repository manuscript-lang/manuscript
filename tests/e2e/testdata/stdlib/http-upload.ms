import expect_equal from "@std/test.ms"
import {headers, HttpClientOptions, HttpMethod, HttpRequest, HttpResponse, buffered} from "@std/http.ms"
import {IoError, ReadStream, read_all} from "@std/io.ms"
import body_stream from "@std/sse.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"

# Hands out its parts one chunk at a time, then reports the end of the stream.
type Chunks:
    parts: List[String]
    next: Int = 0
    failure: Optional[String] = none

impl ReadStream for Chunks:
    fn close() Unit:
        return unit

    var fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]:
        if self.next == self.parts.length():
            match self.failure:
                some(message): return error(IoError.Failed(message.clone()))
                none: return ok(none)

        let chunk = self.parts[self.next]
        self.next += 1
        return ok(some(chunk.to_bytes()))

fn echo(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: request.body.clone())

test "request_stream uploads each chunk of a ReadStream":
    let server = try network().serve("127.0.0.1:0", buffered(echo))
    let client = try network().http_client(HttpClientOptions())
    let upload = Chunks(parts: ["alpha ", "beta ", "gamma"])
    let response = try client.request_stream(
        HttpMethod.Post, "http://{server.address()}/", headers(), upload
    )
    try expect_equal(response.metadata().status, 200)

    let body = try read_all(body_stream(response))
    try expect_equal(body, "alpha beta gamma".to_bytes())

test "request_stream reports a failing ReadStream":
    let server = try network().serve("127.0.0.1:0", buffered(echo))
    let client = try network().http_client(HttpClientOptions())
    let upload = Chunks(parts: ["partial"], failure: some("disk gone"))
    let sent = client.request_stream(
        HttpMethod.Post, "http://{server.address()}/", headers(), upload
    )
    try expect_equal(sent.is_error(), true)

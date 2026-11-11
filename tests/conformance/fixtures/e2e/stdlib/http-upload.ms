// conform: tags=control-flow,faults,interfaces,modules,records,stdlib-http,stdlib-io,stdlib-net,stdlib-sse,stdlib-testing,testing,tier-io,try-result,scope-cleanup
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/http-upload.ms
import expect_equal from "@std/test/test.ms"
import (
    headers,
    HttpClientOptions,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    buffered
) from "@std/net/http.ms"
import ReadStream, Source from "@std/io/io.ms"
import http_client, serve from "@std/net/net.ms"
import Bytes, join from "@std/bytes.ms"

// Reads `input` to its end and joins the chunks.
fn read_to_end(var input: ReadStream[Bytes]) Bytes!:
    var chunks: List[Bytes] = []

    while true:
        chunk := input.next()?

        if bytes := chunk:
            chunks.append(bytes)
        else:
            break

    return ok(join(chunks))

// Hands out its parts one chunk at a time, then reports the end of the stream.
type Chunks:
    parts: List[String]
    next: Int = 0
    failure: String?

impl Source[Bytes] for Chunks:
    var fn close() Unit!:
        return ok(unit)

    var fn next() Bytes?!:
        if self.next == self.parts.length():
            match self.failure:
                message: return error(
                    Error(
                        message.clone(), kind: "EIO"
                    )
                )
                none: return ok(none)

        chunk := self.parts[self.next]
        self.next += 1
        return ok(chunk.to_bytes())

fn echo(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: request.body.clone())

test "request_stream uploads each chunk of a ReadStream":
    server := serve("127.0.0.1:0", buffered(echo))?
    client := http_client(HttpClientOptions())?
    upload := ReadStream[Bytes](Chunks(parts: ["alpha ", "beta ", "gamma"]))
    var response = client.request_stream(
        HttpMethod.Post, "http://{server.address()}/", headers(), upload
    )?
    expect_equal(response.metadata.status, 200)?

    body := read_to_end(var response.body)?
    expect_equal(body, "alpha beta gamma".to_bytes())?

test "request_stream reports a failing ReadStream":
    server := serve("127.0.0.1:0", buffered(echo))?
    client := http_client(HttpClientOptions())?
    upload := ReadStream[Bytes](Chunks(parts: ["partial"], failure: "disk gone"))
    sent := client.request_stream(
        HttpMethod.Post, "http://{server.address()}/", headers(), upload
    )
    expect_equal(sent.is_error(), true)?

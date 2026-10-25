from "@std/web_cache.ms" import ResponseCache
from "@std/http.ms" import Request, Response, Body, headers, text_response
from "@std/testing.ms" import expect_equal, expect_true
from "@std/shared.ms" import share
from "@std/time.ms" import sleep

def payload(response: Response) -> String:
    match response.body:
        case Buffered(data): return data.decode_utf8().get()
        case _: return ""

test "response cache snapshots headers and supports tag and path invalidation":
    let cache = ResponseCache()
    let calls = share(0)

    let handler = lambda (request: Request) -> Response:
        let count = calls.take() + 1
        calls.put(count)
        return text_response(f"{count}")

    let first = cache.handle(Request(path: "/a"), handler, ["page"])
    first.headers.append("Set-Cookie", "late=mutation".to_bytes()).get()

    let hit = cache.handle(Request(path: "/a"), handler)
    try expect_equal(payload(hit), "1")
    try expect_true(hit.headers.values("Set-Cookie").is_none())
    cache.invalidate_tag("page")
    try expect_equal(payload(cache.handle(Request(path: "/a"), handler)), "2")
    cache.invalidate_path("/a")
    try expect_equal(payload(cache.handle(Request(path: "/a"), handler)), "3")
    cache.clear()
    try expect_equal(cache.state.get().entries.length(), 0)

test "cache expiry eviction and sensitive request bypass are bounded":
    let cache = ResponseCache(max_entries: 1, ttl: 2.milliseconds)
    let handler: Callable[[Request], Response] = lambda request: text_response(
        request.path
    )
    cache.handle(Request(path: "/a"), handler)
    cache.handle(Request(path: "/b"), handler)
    try expect_equal(cache.state.get().entries.length(), 1)
    try expect_equal(cache.state.get().entries[0].path, "/b")
    sleep(3.milliseconds)
    cache.handle(Request(path: "/c"), handler)
    try expect_equal(cache.state.get().entries[0].path, "/c")

    for name in ["Cookie", "Authorization", "Range", "If-None-Match"]:
        let fields = headers()
        try fields.append(name, "private".to_bytes())
        cache.handle(Request(path: "/private", headers: fields), handler)
        try expect_equal(cache.state.get().entries[0].path, "/c")

    let tiny = ResponseCache(max_bytes: 1)
    tiny.handle(Request(), handler)
    try expect_equal(tiny.state.get().entries.length(), 0)

test "invalidation during a cache miss suppresses stale insertion":
    let cache = ResponseCache()
    let same = cache.clone()

    let response = cache.handle(
        Request(),
        lambda request:
            same.invalidate_path("/")
            return text_response("old")
    )

    try expect_equal(payload(response), "old")
    try expect_equal(cache.state.get().entries.length(), 0)

    for field in ["Set-Cookie", "Vary", "Content-Range"]:
        cache.handle(
            Request(),
            lambda request:
                let response = text_response("private")
                response.headers.append(field, "*".to_bytes()).get()
                return response
        )

    try expect_equal(cache.state.get().entries.length(), 0)

test "path invalidation does not interpret an empty tag as another filter":
    let cache = ResponseCache()
    cache.handle(Request(path: "/b"), lambda request: text_response("b"), [""])
    cache.invalidate_path("/a")
    try expect_equal(cache.state.get().entries.length(), 1)
    cache.invalidate_tag("")
    try expect_equal(cache.state.get().entries.length(), 0)

from "@std/core.ms" import Closeable
from "@std/http.ms" import Request, Response, Body, HttpMethod, HttpHeaders
from "@std/time.ms" import Instant, Duration, clock
from "@std/shared.ms" import Shared, share

# One immutable buffered response snapshot and its invalidation metadata.
export type CachedResponse:
    # Cache key, including transport scheme, host, path and query.
    key: String
    # Exact path for path invalidation.
    path: String
    # Application invalidation tags, bounded on insertion.
    tags: List[String]
    # Independent header membership and immutable payload.
    response: Response
    # Monotonic insertion time used to determine freshness.
    created: Instant
    # Payload and bounded metadata bytes charged to this entry.
    bytes: Int

# Internal per-member cache state; no state borrow spans application execution.
export type ResponseCacheState:
    # Oldest access first; bounded by entry count and bytes.
    entries: List[CachedResponse] = []
    # Current payload and metadata bytes charged to stored entries.
    bytes: Int = 0
    # Invalidation generation prevents stale in-flight insertion.
    generation: Int = 0

# Explicit per-member cache for public buffered 200 GET responses.
# Authentication, cookies, Vary, conditional/range requests and private/no-store policies bypass it.
export type ResponseCache:
    # Maximum entries; zero disables storage.
    max_entries: Int = 128
    # Maximum total payload plus key/header/tag bytes.
    max_bytes: Int = 8388608
    # Positive monotonic freshness duration; nonpositive disables storage.
    ttl: Duration = 30.seconds
    # Internal shared state; copies share this member's cache.
    state: Shared[ResponseCacheState] = share(ResponseCacheState())

type CachePlan:
    key: Optional[String] = none
    generation: Int = 0
    hit: Optional[Response] = none

type CacheHeld[T]:
    value: T

impl Closeable for CacheHeld[T]:
    var def close() -> Unit: ()

extern def msrt_shield_enter() -> Unit

extern def msrt_shield_exit() -> Unit

type CacheTransaction:
    active: Bool = True

impl Closeable for CacheTransaction:
    var def close() -> Unit: msrt_shield_exit()

impl ResponseCache:
    # Returns a cloned fresh response or invokes produce without holding cache state.
    # Concurrent misses may compute independently. Invalidation suppresses older in-flight insertions.
    def handle(
        request: Request,
        produce: Callable[[Request], Response],
        tags: List[String] = []
    ) -> Response:
        with CacheHeld(cache_lookup(self, request)) as plan:
            if plan.value.hit.is_some(): return plan.value.hit.get().clone()
            if plan.value.key.is_none(): return produce(request)

            with CacheHeld(produce(request)) as response:
                cache_store(self, plan.value, request, response.value, tags)
                return response.value.clone()

    # Removes every entry and prevents pending misses from repopulating older data.
    def clear() -> Unit: self.invalidate(none, none)

    # Invalidates one exact path in this member; coordinate calls across members explicitly.
    def invalidate_path(path: String) -> Unit: self.invalidate(some(path.clone()), none)

    # Invalidates entries with one tag in this member and suppresses older pending insertions.
    def invalidate_tag(tag: String) -> Unit: self.invalidate(none, some(tag.clone()))

    # Internal bounded invalidation; generation saturation disables later insertion.
    def invalidate(path: Optional[String], tag: Optional[String]) -> Unit:
        msrt_shield_enter()

        with CacheTransaction() as transaction:
            var state = self.state.take()
            if state.generation < 9223372036854775807: state.generation += 1

            var entries = List[CachedResponse]()

            for entry in state.entries:
                if (
                    (path.is_none() and tag.is_none())
                    or (path.is_some() and entry.path == path.get())
                    or (
                        tag.is_some()
                        and entry.tags.contains(tag.get())
                    )
                ): state.bytes -= entry.bytes
                else: entries.append(entry.clone())

            state.entries = entries
            self.state.put(state)

def header_budget(fields: HttpHeaders) -> Optional[Int]:
    let names = fields.names()
    if names.length() > 64: return none

    var remaining = 8192

    for name in names:
        if name.byte_length() > remaining: return none

        remaining -= name.byte_length()

        let values = fields.values(name).get()
        if values.length() > 64: return none

        for value in values:
            if value.length() > remaining: return none

            remaining -= value.length()

    return some(8192 - remaining)

def prohibits_cache(fields: HttpHeaders) -> Bool:
    if header_budget(fields).is_none(): return True

    let values = fields.text("Cache-Control")
    if values.is_error(): return True
    if values.get().is_none(): return False

    for value in values.get().get():
        for directive in value.lower().split(","):
            let name = directive.trim().split("=") [0]
            if ["private", "no-store", "no-cache", "max-age", "s-maxage"].contains(name): return True

    return False

def eligible_request(request: Request) -> Bool:
    if request.method != HttpMethod.Get or prohibits_cache(request.headers): return False

    for name in [
        "Authorization", "Cookie", "Range", "If-Range", "If-Match", "If-None-Match",
        "If-Modified-Since", "If-Unmodified-Since", "Pragma"
    ]:
        if request.headers.values(name).is_some(): return False
    return True

def cache_key(request: Request) -> Optional[String]:
    if (
        request.path.byte_length() > 2048
        or request.query.byte_length() > 2048
        or request.scheme.byte_length() > 8
    ): return none

    let host = request.headers.text("Host")
    if host.is_error(): return none

    var authority = ""

    if let values = host.get():
        if values.length() != 1 or values[0].byte_length() > 255: return none

        authority = values[0].clone()

    return some(
        f"{request.scheme.byte_length()}:{request.scheme}{authority.byte_length()}:{authority}{request.path.byte_length()}:{request.path}{request.query}"
    )

def response_charge(
    response: Response,
    key: String,
    path: String,
    tags: List[String]
) -> Optional[Int]:
    if response.status != 200 or prohibits_cache(response.headers): return none

    for name in [
        "Set-Cookie", "Vary", "Content-Range", "WWW-Authenticate", "Expires", "Age"
    ]:
        if response.headers.values(name).is_some(): return none
    if tags.length() > 16: return none

    var size = (
        key.byte_length()
        + path.byte_length()
        + header_budget(response.headers).get()
    )

    for tag in tags:
        if tag.byte_length() > 128: return none

        size += tag.byte_length()

    match response.body:
        case Buffered(data):
            if (
                response.content_length.is_some()
                and response.content_length.get() != data.length()
            ): return none
            if data.length() > 9223372036854775807 - size: return none

            return some(size + data.length())
        case _: return none

def snapshot(response: Response) -> Response:
    return Response(
        response.status, response.headers.clone(), response.body.clone(),
        response.content_length.clone()
    )

def cache_lookup(cache: ResponseCache, request: Request) -> CachePlan:
    msrt_shield_enter()

    with CacheTransaction() as transaction:
        if (
            cache.max_entries <= 0
            or cache.max_bytes < 0
            or cache.ttl.to_nanoseconds() <= 0
            or not eligible_request(request)
        ): return CachePlan()

        let key = cache_key(request)
        if key.is_none(): return CachePlan()

        let now = clock().now()
        var state = cache.state.take()
        var retained = List[CachedResponse]()
        var hit: Optional[CachedResponse] = none

        for entry in state.entries:
            if (
                now.difference(
                    entry.created
                ).to_nanoseconds() >= cache.ttl.to_nanoseconds()
            ):
                state.bytes -= entry.bytes
            elif entry.key == key.get(): hit = some(entry.clone())
            else: retained.append(entry.clone())

        if let entry = hit: retained.append(entry.clone())
        state.entries = retained

        let generation = state.generation + 0
        cache.state.put(state)
        if let entry = hit: return CachePlan(
            key, generation, some(snapshot(entry.response))
        )

        return CachePlan(key, generation)

def cache_store(
    cache: ResponseCache,
    plan: CachePlan,
    request: Request,
    response: Response,
    tags: List[String]
) -> Unit:
    msrt_shield_enter()

    with CacheTransaction() as transaction:
        let charge = response_charge(response, plan.key.get(), request.path, tags)
        if charge.is_none() or charge.get() > cache.max_bytes: return

        var updated = cache.state.take()

        if (
            updated.generation != plan.generation
            or updated.generation == 9223372036854775807
        ):
            cache.state.put(updated)
            return

        var entries = List[CachedResponse]()

        for entry in updated.entries:
            if entry.key == plan.key.get(): updated.bytes -= entry.bytes
            else: entries.append(entry.clone())

        while (
            entries.length() > 0
            and (
                entries.length() >= cache.max_entries
                or updated.bytes > cache.max_bytes - charge.get()
            )
        ):
            updated.bytes -= entries[0].bytes
            entries.remove(0)

        entries.append(
            CachedResponse(
                plan.key.get().clone(), request.path.clone(), tags.clone(),
                snapshot(response), clock().now(), charge.get()
            )
        )
        updated.entries = entries
        updated.bytes += charge.get()
        cache.state.put(updated)
        return

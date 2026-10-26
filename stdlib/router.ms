# Request routing and middleware over `HttpExchange`, implemented in Manuscript.
from "@std/bytes.ms" import Bytes, BytesBuilder
from "@std/http.ms" import (
    headers,
    HttpError,
    HttpExchange,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    reply,
    text
)
from "@std/io.ms" import IoError
from "@std/net.ms" import WebSocket, WebSocketError
from "@std/log.ms" import Logger, LogLevel, record
from "@std/random.ms" import entropy, uuid_v4
from "@std/time.ms" import clock
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock

# Errors returned while registering a route.
export type RouterError:
    # The pattern is not a path of literal segments, `:name` parameters and a final `*name` wildcard, or it repeats a name.
    case InvalidPattern(
        # The pattern text that failed to parse or repeated a capture name.
        pattern: String
    )
    # A route for this method and pattern shape is already registered.
    case Duplicate(
        # The method token of the existing route.
        method: String,
        # The pattern that was registered twice.
        pattern: String
    )

impl Error for RouterError:
    # Returns `router: invalid pattern <pattern>` or `router: duplicate route <method> <pattern>`.
    def message() -> String:
        match self:
            case InvalidPattern(pattern): return f"router: invalid pattern {pattern}"
            case Duplicate(method, pattern): return f"router: duplicate route {method} {pattern}"

# The values a matched pattern captured, by name.
export type RouteParams:
    # Names in pattern order.
    names: List[String]
    # The captured text for each name; a wildcard holds the remaining segments joined by `/`.
    values: List[String]

impl RouteParams:
    # Returns the text captured for `name`, or none when the pattern has no such parameter.
    def get(name: String) -> Optional[String]:
        if let index = self.names.index_of(name):
            return some(self.values[index].clone())

        return none

# One segment of a route pattern.
export type Segment:
    # Matches exactly this text.
    case Literal(
        # The exact text a request path segment must equal, case-sensitively.
        text: String
    )
    # Matches one nonempty segment and captures it.
    case Param(
        # The name `RouteParams.get` finds the captured segment under.
        name: String
    )
    # Matches the rest of the path, possibly nothing, and captures it joined by `/`.
    case Rest(
        # The name `RouteParams.get` finds the remaining path under.
        name: String
    )

# A registered route: the method token and pattern it answers, and the handler that runs on a match.
export type Route:
    # The method token the route answers, such as `GET`.
    method: String
    # The pattern text as registered.
    pattern: String
    # The pattern split at `/` into segments, in path order.
    segments: List[Segment]
    # Middleware of the routers this route was mounted through, outermost first.
    around: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ]
    # Runs when the route matches, with the values the pattern captured.
    handler: Callable[[HttpExchange, RouteParams], Result[Unit, HttpError]]

# Routes requests by method and path and wraps them in middleware.
#
# Patterns are `/` followed by literal segments, `:name` parameters that match one segment, and
# a final `*name` that matches the rest of the path (possibly nothing). The first route
# registered that matches wins, and a trailing slash is part of the path.
export type Router:
    # Registered routes in registration order.
    routes: List[Route] = []
    # Middleware in the order it wraps requests: the first one added runs outermost.
    middleware: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ] = []

impl Router:
    # Registers `handler` for `method` and `pattern`.
    # A route also answers HEAD when `method` is GET and no HEAD route matches. Registering the
    # same method and pattern shape twice returns Duplicate.
    var def route(
        method: HttpMethod,
        pattern: String,
        handler: Callable[[HttpExchange, RouteParams], Result[Unit, HttpError]]
    ) -> Result[Unit, RouterError]:
        let segments = try parse_pattern(pattern.clone())
        return insert(var self.routes, method.text(), pattern, segments, [], handler)

    # Registers every route of `routes` under `prefix`, wrapped in that router's own middleware.
    # The prefix is `/` followed by segments with no trailing slash, and it may hold parameters.
    # The mounted router's `/` route answers `prefix` itself. Later changes to `routes` do not
    # reach this router.
    var def mount(prefix: String, routes: Router) -> Result[Unit, RouterError]:
        if prefix.ends_with("/") and prefix != "/":
            return error(RouterError.InvalidPattern(prefix.clone()))

        let base = "" if prefix == "/" else prefix.clone()

        for source in routes.routes:
            let tail = "" if source.pattern == "/" else source.pattern.clone()

            let pattern = base + tail if not (base + tail).is_empty() else "/"

            let segments = try parse_pattern(pattern.clone())
            let around = routes.middleware.concat(source.around)
            try insert(
                var self.routes, source.method.clone(), pattern, segments, around,
                source.handler
            )

        return ok(())

    # Adds middleware around every route and around the 404, 405 and OPTIONS answers.
    # It receives the exchange and a continuation that runs the rest of the chain with the exchange
    # it is given, so a middleware can pass on a wrapped one (see `request_id` and `access_log`).
    var def use(
        middleware: Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ) -> Unit:
        self.middleware.append(middleware)

    # Returns the function to pass to `serve`.
    # Unmatched paths answer 404, a path matched only under other methods answers 405 with
    # `Allow`, and OPTIONS on a known path answers 204 with `Allow`.
    def handler() -> Callable[[HttpExchange], Result[Unit, HttpError]]:
        let routes = self.routes.clone()
        let middleware = self.middleware.clone()
        return lambda exchange: dispatch(routes.clone(), middleware.clone(), exchange)

# Adds a route unless one with the same method and shape exists.
def insert(
    var routes: List[Route],
    token: String,
    pattern: String,
    segments: List[Segment],
    around: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ],
    handler: Callable[[HttpExchange, RouteParams], Result[Unit, HttpError]]
) -> Result[Unit, RouterError]:
    let shape = shape_of(segments)
    for existing in routes:
        if existing.method == token and shape_of(existing.segments) == shape:
            return error(RouterError.Duplicate(token, pattern.clone()))
    routes.append(
        Route(
            method: token, pattern: pattern, segments: segments, around: around,
            handler: handler
        )
    )
    return ok(())

# The end of a chain held by value so a closure can own it.
type Tail:
    last: Callable[[HttpExchange], Result[Unit, HttpError]]

# Parses `pattern` into segments, rejecting empty or repeated names and a wildcard that is not last.
def parse_pattern(pattern: String) -> Result[List[Segment], RouterError]:
    if not pattern.starts_with("/"): return error(
        RouterError.InvalidPattern(pattern.clone())
    )

    var segments: List[Segment] = []
    var names: List[String] = []
    let parts = split_path(pattern)

    for entry in parts.entries():
        let segment = segment_of(entry.value)
        let last = entry.index == parts.length() - 1
        if not valid_segment(segment, names, last):
            return error(RouterError.InvalidPattern(pattern))

        if let name = segment_name(segment): names.append(name)
        segments.append(segment)

    return ok(segments)

# The segments of an absolute path; "/" has none.
def split_path(path: String) -> List[String]:
    if path == "/": return []

    return path.drop(1).split("/")

def segment_of(part: String) -> Segment:
    if part.starts_with(":"): return Segment.Param(part.drop(1))
    if part.starts_with("*"): return Segment.Rest(part.drop(1))

    return Segment.Literal(part.clone())

def segment_name(segment: Segment) -> Optional[String]:
    match segment:
        case Literal(_): return none
        case Param(name): return some(name.clone())
        case Rest(name): return some(name.clone())

def valid_segment(segment: Segment, names: List[String], last: Bool) -> Bool:
    match segment:
        case Literal(text): return not text.is_empty() or last
        case Param(name): return not name.is_empty() and not names.contains(name)
        case Rest(name): return (
            last
            and not name.is_empty()
            and not names.contains(name)
        )

# Patterns with the same shape match the same paths, whatever their parameter names.
def shape_of(segments: List[Segment]) -> String:
    return segments.map(lambda segment: shape_text(segment)).join("/")

def shape_text(segment: Segment) -> String:
    match segment:
        case Literal(text): return f"={text}"
        case Param(_): return ":"
        case Rest(_): return "*"

# What the routes say about one request path.
type Lookup:
    # The matching route for the method, if any.
    found: Optional[Int]
    # Captures of that route.
    params: RouteParams
    # Methods that have a route for the path, for `Allow`.
    allow: List[String]

def lookup(routes: List[Route], method: String, parts: List[String]) -> Lookup:
    var found: Optional[Int] = none
    var fallback = False
    var params = RouteParams(names: [], values: [])
    var allow: List[String] = []

    for entry in routes.entries():
        if let captured = capture(entry.value.segments, parts):
            allow.append(entry.value.method.clone())

            if (
                serves(entry.value.method, method)
                and (
                    found.is_none()
                    or (fallback and entry.value.method == method)
                )
            ):
                found = some(entry.index)
                fallback = entry.value.method != method
                params = RouteParams(
                    names: names_of(entry.value.segments), values: captured
                )

    return Lookup(found: found, params: params, allow: allow)

# A GET route also serves HEAD.
def serves(registered: String, requested: String) -> Bool:
    return registered == requested or (registered == "GET" and requested == "HEAD")

def names_of(segments: List[Segment]) -> List[String]:
    return segments.flat_map(lambda segment: name_list(segment))

def name_list(segment: Segment) -> List[String]:
    if let name = segment_name(segment): return [name]

    return []

# The captured values when `parts` match `segments`.
def capture(segments: List[Segment], parts: List[String]) -> Optional[List[String]]:
    var values: List[String] = []

    for entry in segments.entries():
        if take_rest(entry.value):
            values.append(parts.drop(entry.index).join("/"))
            return some(values)

        if entry.index >= parts.length(): return none
        if not accepts(entry.value, parts[entry.index], var values): return none

    if parts.length() != segments.length(): return none

    return some(values)

def take_rest(segment: Segment) -> Bool:
    match segment:
        case Rest(_): return True
        case _: return False

# Whether `segment` matches `part`; a parameter adds the text to `values`.
def accepts(segment: Segment, part: String, var values: List[String]) -> Bool:
    match segment:
        case Literal(text): return text == part
        case Param(_):
            if part.is_empty(): return False

            values.append(part.clone())
            return True
        case Rest(_): return True

def dispatch(
    routes: List[Route],
    middleware: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ],
    exchange: HttpExchange
) -> Result[Unit, HttpError]:
    let method = exchange.method().text()
    let found = lookup(routes, method, split_path(exchange.path()))
    return chain(middleware, 0, exchange, final_step(routes, method, found))

def chain(
    middleware: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ],
    at: Int,
    exchange: HttpExchange,
    last: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    if at >= middleware.length(): return last(exchange)

    return middleware[at](exchange, next_step(middleware, at + 1, last))

# The end of the chain: the matched route, or the 404, 405 or OPTIONS answer.
def final_step(
    routes: List[Route],
    method: String,
    found: Lookup
) -> Callable[[HttpExchange], Result[Unit, HttpError]]:
    return lambda exchange: finish(
        routes.clone(), method.clone(), found.clone(), exchange
    )

# The continuation handed to the middleware at `at - 1`.
def next_step(
    middleware: List[
        Callable[
            [
                HttpExchange,
                Callable[[HttpExchange], Result[Unit, HttpError]]
            ],
            Result[Unit, HttpError]
        ]
    ],
    at: Int,
    last: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Callable[[HttpExchange], Result[Unit, HttpError]]:
    let rest = Tail(last: last)
    return lambda exchange: chain(middleware.clone(), at, exchange, rest.last)

# The end of a route's own middleware: its handler.
def route_step(
    routes: List[Route],
    index: Int,
    params: RouteParams
) -> Callable[[HttpExchange], Result[Unit, HttpError]]:
    return lambda exchange: routes[index].handler(exchange, params)

# Runs the matched route, or answers 404, 405 or the OPTIONS listing.
def finish(
    routes: List[Route],
    method: String,
    found: Lookup,
    exchange: HttpExchange
) -> Result[Unit, HttpError]:
    if let index = found.found:
        let around = routes[index].around.clone()
        return chain(
            around, 0, exchange, route_step(routes.clone(), index, found.params.clone())
        )

    if found.allow.is_empty(): return reply(exchange, text(404, "not found\n"))

    let response = text(405 if method != "OPTIONS" else 204, "")
    try response.headers.append("Allow", allow_text(found.allow).to_bytes())
    return reply(exchange, response)

# Methods with a route for the path, sorted and without repeats; GET adds HEAD, and OPTIONS is always answered.
def allow_text(methods: List[String]) -> String:
    var all = methods.clone()
    if all.contains("GET"): all.append("HEAD")
    all.append("OPTIONS")
    return all.distinct().sorted().join(", ")

impl Router:
    # Runs `request` through the router without a socket and returns the response it produced.
    # A handler error is returned as is; the server would answer it with a 500. A handler that
    # sends nothing answers 204.
    def call(request: HttpRequest) -> Result[HttpResponse, HttpError]:
        let state = share(
            TestState(
                status: 0, sent: False, closed: False, head: headers(),
                body: BytesBuilder(), unread: some(request.body.clone())
            )
        )
        let exchange = TestExchange(request: request.clone(), state: state)
        try self.handler()(exchange)
        return finished(state)

# What an in-process handler has sent so far.
type TestState:
    status: Int
    sent: Bool
    closed: Bool
    head: HttpHeaders
    body: BytesBuilder
    unread: Optional[Bytes]

type TestExchange:
    request: HttpRequest
    state: Shared[TestState]

def finished(state: Shared[TestState]) -> Result[HttpResponse, HttpError]:
    with var guard = lock(state):
        if not guard.value.sent:
            return ok(
                HttpResponse(
                    status: 204, headers: headers(), body: "".to_bytes()
                )
            )

        return ok(
            HttpResponse(
                status: guard.value.status, headers: guard.value.head.clone(),
                body: guard.value.body.build()
            )
        )

impl HttpExchange for TestExchange:
    def close() -> Unit:
        with var guard = lock(self.state):
            guard.value.closed = True

    def headers() -> HttpHeaders:
        return self.request.headers

    def method() -> HttpMethod:
        return self.request.method.clone()

    def path() -> String:
        return self.request.path.clone()

    def protocol() -> String:
        return self.request.protocol.clone()

    def query() -> String:
        return self.request.query.clone()

    def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        with var guard = lock(self.state):
            if guard.value.closed: return error(IoError.Closed)

            let chunk = guard.value.unread.clone()
            guard.value.unread = none
            return ok(chunk)

    def send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]:
        if status < 200 or status > 599: return error(HttpError.InvalidInput)
        if headers.values("Content-Length").is_some(): return error(
            HttpError.InvalidInput
        )
        if headers.values("Transfer-Encoding").is_some(): return error(
            HttpError.InvalidInput
        )
        if headers.values("Connection").is_some(): return error(HttpError.InvalidInput)

        with var guard = lock(self.state):
            if guard.value.closed: return error(HttpError.Closed)
            if guard.value.sent: return error(HttpError.InvalidInput)

            guard.value.status = status
            guard.value.head = headers.clone()
            guard.value.sent = True
            return ok(())

    def send(status: Int, headers: HttpHeaders, body: Bytes) -> Result[Unit, HttpError]:
        try self.send_headers(status, headers)
        if self.request.method.text() == "HEAD" or not has_body(status): return ok(())

        with var guard = lock(self.state):
            guard.value.body.append_bytes(body)
            return ok(())

    def upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]:
        return error(WebSocketError.Failed("router: WebSocket upgrades need a server"))

    def write(data: String) -> Result[Unit, IoError]:
        return self.write_bytes(data.to_bytes())

    def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        with var guard = lock(self.state):
            if guard.value.closed: return error(IoError.Closed)
            if not guard.value.sent: return error(IoError.InvalidInput)
            if self.request.method.text() == "HEAD" or not has_body(guard.value.status):
                return error(IoError.InvalidInput)

            guard.value.body.append_bytes(data)
            return ok(())

# Whether a response with this status may carry a body.
def has_body(status: Int) -> Bool:
    return status >= 200 and status != 204 and status != 304

# What a wrapped exchange has sent so far.
type TapState:
    status: Int
    bytes: Int

# An exchange that passes everything to `inner`, adds `extra` to the headers of its response, and counts the status and body bytes sent.
type Tap:
    inner: HttpExchange
    extra: HttpHeaders
    state: Shared[TapState]

def new_tap(inner: HttpExchange, extra: HttpHeaders) -> Tap:
    return Tap(inner: inner, extra: extra, state: share(TapState(status: 0, bytes: 0)))

def counted(state: Shared[TapState], status: Int, bytes: Int) -> Unit:
    with var guard = lock(state):
        if status != 0: guard.value.status = status
        guard.value.bytes += bytes

def snapshot(state: Shared[TapState]) -> TapState:
    with var guard = lock(state):
        return TapState(status: guard.value.status, bytes: guard.value.bytes)

# `sent` plus the `extra` headers it does not already have.
def with_extra(sent: HttpHeaders, extra: HttpHeaders) -> HttpHeaders:
    let all = sent.clone()
    for name in extra.names():
        if all.values(name).is_none():
            for value in extra.values(name).get([]):
                all.append(name, value).get(())
    return all

impl HttpExchange for Tap:
    def close() -> Unit:
        self.inner.close()

    def headers() -> HttpHeaders:
        return self.inner.headers()

    def method() -> HttpMethod:
        return self.inner.method()

    def path() -> String:
        return self.inner.path()

    def protocol() -> String:
        return self.inner.protocol()

    def query() -> String:
        return self.inner.query()

    def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        return self.inner.read(max_bytes)

    def send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]:
        try self.inner.send_headers(status, with_extra(headers, self.extra))
        counted(self.state, status, 0)
        return ok(())

    def send(status: Int, headers: HttpHeaders, body: Bytes) -> Result[Unit, HttpError]:
        try self.inner.send(status, with_extra(headers, self.extra), body)
        counted(self.state, status, body.length())
        return ok(())

    def upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]:
        return self.inner.upgrade(allowed_origins, subprotocols, max_message_bytes)

    def write(data: String) -> Result[Unit, IoError]:
        try self.inner.write(data)
        counted(self.state, 0, data.byte_length())
        return ok(())

    def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        try self.inner.write_bytes(data)
        counted(self.state, 0, data.length())
        return ok(())

# Middleware that gives every request an id: the request's own `X-Request-Id` when it is 1 to 128
# printable ASCII characters, otherwise a new UUID. The id is set on the request headers, where
# handlers and later middleware read it, and added to the response as `X-Request-Id`.
export def request_id() -> Callable[
    [HttpExchange, Callable[[HttpExchange], Result[Unit, HttpError]]],
    Result[Unit, HttpError]
]:
    return lambda exchange, next: with_request_id(exchange, next)

def with_request_id(
    exchange: HttpExchange,
    next: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    let request = exchange.headers()
    let given = try request.text("X-Request-Id")
    var id = ""
    if let values = given: id = values.first().get("")

    if not usable_id(id):
        id = try new_id()
        request.remove("X-Request-Id")
        try request.append("X-Request-Id", id.to_bytes())

    let extra = headers()
    try extra.append("X-Request-Id", id.to_bytes())
    return next(new_tap(exchange, extra))

def usable_id(id: String) -> Bool:
    return (
        id.length() >= 1
        and id.length() <= 128
        and id.scalar_values().all(lambda c: (c > 32 and c < 127))
    )

def new_id() -> Result[String, HttpError]:
    let made = uuid_v4(entropy())
    if made.is_error(): return error(HttpError.Failed(made.err().message()))

    return ok(made.get().clone())

# One request as `access_log` writes it.
type AccessEntry:
    method: String
    path: String
    protocol: String
    status: Int
    bytes: Int
    duration_ms: Int

# Middleware that writes one Info record named `request` to `logger` after each request, with
# the method, path, protocol, response status, body bytes written and duration in milliseconds.
# A handler that sends nothing is logged as 204 and one that fails before sending as 500. A
# logging failure never fails the request.
export def access_log(logger: Logger) -> Callable[
    [HttpExchange, Callable[[HttpExchange], Result[Unit, HttpError]]],
    Result[Unit, HttpError]
]:
    return lambda exchange, next: with_access_log(logger, exchange, next)

def with_access_log(
    logger: Logger,
    exchange: HttpExchange,
    next: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    let started = clock().now()
    let method = exchange.method().text()
    let path = exchange.path()
    let protocol = exchange.protocol()
    let tap = new_tap(exchange, headers())
    let state = tap.state
    let result = next(tap)
    let sent = snapshot(state)
    let status = answered(sent.status, result.is_ok())
    let entry = AccessEntry(
        method: method, path: path, protocol: protocol, status: status,
        bytes: sent.bytes,
        duration_ms: clock().now().difference(started).to_milliseconds()
    )
    let logged = record(logger, LogLevel.Info, "request", entry)
    return result

def answered(status: Int, succeeded: Bool) -> Int:
    if status != 0: return status
    if succeeded: return 204

    return 500

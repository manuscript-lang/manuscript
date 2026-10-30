# Request routing and middleware over `HttpExchange`, implemented in Manuscript.
import Bytes, BytesBuilder from "@std/bytes.ms"
import (
    headers,
    HttpError,
    HttpExchange,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    reply,
    text
) from "@std/http.ms"
import IoError from "@std/io.ms"
import WebSocket, WebSocketError from "@std/net.ms"
import Logger, LogLevel, record from "@std/log.ms"
import entropy, uuid_v4 from "@std/random.ms"
import clock from "@std/time.ms"
import Shared, share from "@std/shared.ms"
import lock from "@std/sync.ms"

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
    fn message() String:
        match self:
            InvalidPattern(pattern): return "router: invalid pattern {pattern}"
            Duplicate(method, pattern): return "router: duplicate route {method} {pattern}"

# The values a matched pattern captured, by name.
export type RouteParams:
    # Names in pattern order.
    names: List[String]
    # The captured text for each name; a wildcard holds the remaining segments joined by `/`.
    values: List[String]

impl RouteParams:
    # Returns the text captured for `name`, or none when the pattern has no such parameter.
    fn get(name: String) Optional[String]:
        if let index = self.names.index_of(name):
            return self.values[index].clone()

        return none

    # Returns the text captured for `name`, or `fallback` when the pattern has no such parameter.
    fn get_or(name: String, fallback: String) String:
        return self.get(name).get(fallback)

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
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ]
    # Runs when the route matches, with the values the pattern captured.
    handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]

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
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ] = []

impl Router:
    # Registers `handler` for `method` and `pattern`.
    # A route also answers HEAD when `method` is GET and no HEAD route matches. Registering the
    # same method and pattern shape twice returns Duplicate.
    var fn route(
        method: HttpMethod,
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        let segments = try parse_pattern(pattern.clone())
        return insert(var self.routes, method.text(), pattern, segments, [], handler)

    # Registers `handler` for GET requests to `pattern`; shorthand for `route(HttpMethod.Get, pattern, handler)`.
    var fn get(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Get, pattern, handler)

    # Registers `handler` for HEAD requests to `pattern`; shorthand for `route(HttpMethod.Head, pattern, handler)`.
    var fn head(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Head, pattern, handler)

    # Registers `handler` for POST requests to `pattern`; shorthand for `route(HttpMethod.Post, pattern, handler)`.
    var fn post(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Post, pattern, handler)

    # Registers `handler` for PUT requests to `pattern`; shorthand for `route(HttpMethod.Put, pattern, handler)`.
    var fn put(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Put, pattern, handler)

    # Registers `handler` for PATCH requests to `pattern`; shorthand for `route(HttpMethod.Patch, pattern, handler)`.
    var fn patch(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Patch, pattern, handler)

    # Registers `handler` for DELETE requests to `pattern`; shorthand for `route(HttpMethod.Delete, pattern, handler)`.
    var fn delete(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Delete, pattern, handler)

    # Registers `handler` for OPTIONS requests to `pattern`; shorthand for `route(HttpMethod.Options, pattern, handler)`.
    var fn options(
        pattern: String,
        handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
    ) Result[Unit, RouterError]:
        return self.route(HttpMethod.Options, pattern, handler)

    # Registers every route of `routes` under `prefix`, wrapped in that router's own middleware.
    # The prefix is `/` followed by segments with no trailing slash, and it may hold parameters.
    # The mounted router's `/` route answers `prefix` itself. Later changes to `routes` do not
    # reach this router.
    var fn mount(prefix: String, routes: Router) Result[Unit, RouterError]:
        if prefix.ends_with("/") and prefix != "/":
            return error(RouterError.InvalidPattern(prefix.clone()))

        let base = if prefix == "/": "" else: prefix.clone()

        for source in routes.routes:
            let tail = if source.pattern == "/": "" else: source.pattern.clone()

            let pattern = if not (base + tail).is_empty(): base + tail else: "/"

            let segments = try parse_pattern(pattern.clone())
            let around = routes.middleware.concat(source.around)
            try insert(
                var self.routes, source.method.clone(), pattern, segments, around,
                source.handler
            )

        return ok(unit)

    # Adds middleware around every route and around the 404, 405 and OPTIONS answers.
    # It receives the exchange and a continuation that runs the rest of the chain with the exchange
    # it is given, so a middleware can pass on a wrapped one (see `request_id` and `access_log`).
    var fn use(
        middleware: fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ) Unit:
        self.middleware.append(middleware)

    # Returns the function to pass to `serve`.
    # Unmatched paths answer 404, a path matched only under other methods answers 405 with
    # `Allow`, and OPTIONS on a known path answers 204 with `Allow`.
    fn handler() fn(HttpExchange) Result[Unit, HttpError]:
        let routes = share(self.routes.clone())
        let middleware = self.middleware.clone()
        return fn exchange: dispatch(routes, middleware.clone(), exchange)

# Adds a route unless one with the same method and shape exists.
fn insert(
    var routes: List[Route],
    token: String,
    pattern: String,
    segments: List[Segment],
    around: List[
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ],
    handler: fn(HttpExchange, RouteParams) Result[Unit, HttpError]
) Result[Unit, RouterError]:
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
    return ok(unit)

# The end of a chain held by value so a closure can own it.
type Tail:
    last: fn(HttpExchange) Result[Unit, HttpError]

# Parses `pattern` into segments, rejecting empty or repeated names and a wildcard that is not last.
fn parse_pattern(pattern: String) Result[List[Segment], RouterError]:
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
fn split_path(path: String) List[String]:
    if path == "/": return []

    return path.drop(1).split("/")

fn segment_of(part: String) Segment:
    if part.starts_with(":"): return Segment.Param(part.drop(1))
    if part.starts_with("*"): return Segment.Rest(part.drop(1))

    return Segment.Literal(part.clone())

fn segment_name(segment: Segment) Optional[String]:
    match segment:
        Literal(_): return none
        Param(name): return name.clone()
        Rest(name): return name.clone()

fn valid_segment(segment: Segment, names: List[String], last: Bool) Bool:
    match segment:
        Literal(text): return not text.is_empty() or last
        Param(name): return not name.is_empty() and not names.contains(name)
        Rest(name): return (last and not name.is_empty() and not names.contains(name))

# Patterns with the same shape match the same paths, whatever their parameter names.
fn shape_of(segments: List[Segment]) String:
    return segments.map(fn segment: shape_text(segment)).join("/")

fn shape_text(segment: Segment) String:
    match segment:
        Literal(text): return "={text}"
        Param(_): return ":"
        Rest(_): return "*"

# What the routes say about one request path.
type Lookup:
    # The matching route for the method, if any.
    found: Optional[Int]
    # Captures of that route.
    params: RouteParams
    # Methods that have a route for the path, for `Allow`.
    allow: List[String]

fn lookup(routes: List[Route], method: String, parts: List[String]) Lookup:
    var found: Optional[Int] = none
    var fallback = false
    var params = RouteParams(names: [], values: [])
    var allow: List[String] = []
    var index = 0

    while index < routes.length():
        let route = routes[index]

        if let captured = capture(route.segments, parts):
            allow.append(route.method.clone())

            if (
                serves(route.method, method)
                and (
                    found.is_none()
                    or (fallback and route.method == method)
                )
            ):
                found = index
                fallback = route.method != method
                params = RouteParams(names: names_of(route.segments), values: captured)

        index += 1

    return Lookup(found: found, params: params, allow: allow)

# A GET route also serves HEAD.
fn serves(registered: String, requested: String) Bool:
    return registered == requested or (registered == "GET" and requested == "HEAD")

fn names_of(segments: List[Segment]) List[String]:
    return segments.flat_map(fn segment: name_list(segment))

fn name_list(segment: Segment) List[String]:
    if let name = segment_name(segment): return [name]

    return []

# The captured values when `parts` match `segments`.
fn capture(segments: List[Segment], parts: List[String]) Optional[List[String]]:
    var values: List[String] = []

    for entry in segments.entries():
        if take_rest(entry.value):
            values.append(parts.drop(entry.index).join("/"))
            return values

        if entry.index >= parts.length(): return none
        if not accepts(entry.value, parts[entry.index], var values): return none

    if parts.length() != segments.length(): return none

    return values

fn take_rest(segment: Segment) Bool:
    match segment:
        Rest(_): return true
        _: return false

# Whether `segment` matches `part`; a parameter adds the text to `values`.
fn accepts(segment: Segment, part: String, var values: List[String]) Bool:
    match segment:
        Literal(text): return text == part
        Param(_):
            if part.is_empty(): return false

            values.append(part.clone())
            return true
        Rest(_): return true

fn dispatch(
    routes: Shared[List[Route]],
    middleware: List[
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ],
    exchange: HttpExchange
) Result[Unit, HttpError]:
    let method = exchange.method().text()
    let found = lookup(routes.get(), method, split_path(exchange.path()))
    return chain(middleware, 0, exchange, final_step(routes, method, found))

fn chain(
    middleware: List[
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ],
    at: Int,
    exchange: HttpExchange,
    last: fn(HttpExchange) Result[Unit, HttpError]
) Result[Unit, HttpError]:
    if at >= middleware.length(): return last(exchange)

    return middleware[at](exchange, next_step(middleware, at + 1, last))

# The end of the chain: the matched route, or the 404, 405 or OPTIONS answer.
fn final_step(
    routes: Shared[List[Route]],
    method: String,
    found: Lookup
) fn(HttpExchange) Result[Unit, HttpError]:
    return fn exchange: finish(routes, method.clone(), found.clone(), exchange)

# The continuation handed to the middleware at `at - 1`.
fn next_step(
    middleware: List[
        fn(
            HttpExchange,
            fn(HttpExchange) Result[Unit, HttpError]
        ) Result[Unit, HttpError]
    ],
    at: Int,
    last: fn(HttpExchange) Result[Unit, HttpError]
) fn(HttpExchange) Result[Unit, HttpError]:
    let rest = Tail(last: last)
    return fn exchange: chain(middleware.clone(), at, exchange, rest.last)

# The end of a route's own middleware: its handler.
fn route_step(
    routes: Shared[List[Route]],
    index: Int,
    params: RouteParams
) fn(HttpExchange) Result[Unit, HttpError]:
    return fn exchange: routes.get() [index].handler(exchange, params)

# Runs the matched route, or answers 404, 405 or the OPTIONS listing.
fn finish(
    routes: Shared[List[Route]],
    method: String,
    found: Lookup,
    exchange: HttpExchange
) Result[Unit, HttpError]:
    if let index = found.found:
        let around = routes.get() [index].around.clone()
        return chain(
            around, 0, exchange, route_step(routes, index, found.params.clone())
        )

    if found.allow.is_empty(): return reply(exchange, text(404, "not found\n"))

    let response = text(if method != "OPTIONS": 405 else: 204, "")
    try response.headers.append("Allow", allow_text(found.allow))
    return reply(exchange, response)

# Methods with a route for the path, sorted and without repeats; GET adds HEAD, and OPTIONS is always answered.
fn allow_text(methods: List[String]) String:
    var all = methods.clone()
    if all.contains("GET"): all.append("HEAD")
    all.append("OPTIONS")
    return all.distinct().sorted().join(", ")

impl Router:
    # Runs `request` through the router without a socket and returns the response it produced.
    # A handler error is returned as is; the server would answer it with a 500. A handler that
    # sends nothing answers 204.
    fn call(request: HttpRequest) Result[HttpResponse, HttpError]:
        let state = share(
            TestState(
                status: 0, sent: false, complete: false, closed: false, head: headers(),
                body: BytesBuilder(), unread: request.body.clone()
            )
        )
        let exchange = TestExchange(request: request.clone(), state: state)
        try self.handler()(exchange)
        return finished(state)

# What an in-process handler has sent so far.
type TestState:
    status: Int
    sent: Bool
    complete: Bool
    closed: Bool
    head: HttpHeaders
    body: BytesBuilder
    unread: Optional[Bytes]

type TestExchange:
    request: HttpRequest
    state: Shared[TestState]

fn finished(state: Shared[TestState]) Result[HttpResponse, HttpError]:
    var guard = lock(state)
    if not guard.value.sent:
        return ok(HttpResponse(status: 204, headers: headers(), body: "".to_bytes()))

    return ok(
        HttpResponse(
            status: guard.value.status, headers: guard.value.head.clone(),
            body: guard.value.body.drain()
        )
    )

impl HttpExchange for TestExchange:
    fn close() Unit:
        var guard = lock(self.state)
        guard.value.closed = true

    fn headers() HttpHeaders:
        return self.request.headers

    fn method() HttpMethod:
        return self.request.method.clone()

    fn path() String:
        return self.request.path.clone()

    fn protocol() String:
        return self.request.protocol.clone()

    fn query() String:
        return self.request.query.clone()

    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]:
        let requested = max_bytes.get(65536)
        if requested <= 0: return error(IoError.InvalidInput)

        let max = if requested > 65536: 65536 else: requested

        var guard = lock(self.state)
        if guard.value.closed: return error(IoError.Closed)

        let chunk = guard.value.unread.clone()
        guard.value.unread = none

        if let bytes = chunk:
            if bytes.length() == 0: return ok(none)

            let n = if max < bytes.length(): max else: bytes.length()

            if n < bytes.length():
                guard.value.unread = bytes.slice(n, bytes.length()).get()
            return ok(bytes.slice(0, n).get())

        return ok(none)

    fn send_headers(status: Int, headers: HttpHeaders) Result[Unit, HttpError]:
        if status < 200 or status > 599: return error(HttpError.InvalidInput)
        if headers.contains("Content-Length"): return error(HttpError.InvalidInput)
        if headers.contains("Transfer-Encoding"): return error(HttpError.InvalidInput)
        if headers.contains("Connection"): return error(HttpError.InvalidInput)

        var guard = lock(self.state)
        if guard.value.closed: return error(HttpError.Closed)
        if guard.value.sent: return error(HttpError.InvalidInput)

        guard.value.status = status
        guard.value.head = headers.clone()
        guard.value.sent = true
        return ok(unit)

    fn send(status: Int, headers: HttpHeaders, body: Bytes) Result[Unit, HttpError]:
        try self.send_headers(status, headers)

        var guard = lock(self.state)
        guard.value.complete = true
        if self.request.method.text() == "HEAD" or not has_body(status): return ok(unit)

        guard.value.body.append_bytes(body)
        return ok(unit)

    fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) Result[WebSocket, WebSocketError]:
        return error(WebSocketError.Failed("router: WebSocket upgrades need a server"))

    fn write(data: String) Result[Unit, IoError]:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Result[Unit, IoError]:
        var guard = lock(self.state)
        if guard.value.closed: return error(IoError.Closed)
        if not guard.value.sent or guard.value.complete: return error(
            IoError.InvalidInput
        )
        if self.request.method.text() == "HEAD" or not has_body(guard.value.status):
            return error(IoError.InvalidInput)

        guard.value.body.append_bytes(data)
        return ok(unit)

# Whether a response with this status may carry a body.
fn has_body(status: Int) Bool:
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

fn new_tap(inner: HttpExchange, extra: HttpHeaders) Tap:
    return Tap(inner: inner, extra: extra, state: share(TapState(status: 0, bytes: 0)))

fn counted(state: Shared[TapState], status: Int, bytes: Int) Unit:
    var guard = lock(state)
    if status != 0: guard.value.status = status
    guard.value.bytes += bytes

fn snapshot(state: Shared[TapState]) TapState:
    var guard = lock(state)
    return TapState(status: guard.value.status, bytes: guard.value.bytes)

# `sent` plus the `extra` headers it does not already have.
fn with_extra(sent: HttpHeaders, extra: HttpHeaders) HttpHeaders:
    let all = sent.clone()
    for name in extra.names():
        if not all.contains(name):
            for value in extra.values(name):
                all.append(name, value).get(unit)
    return all

impl HttpExchange for Tap:
    fn close() Unit:
        self.inner.close()

    fn headers() HttpHeaders:
        return self.inner.headers()

    fn method() HttpMethod:
        return self.inner.method()

    fn path() String:
        return self.inner.path()

    fn protocol() String:
        return self.inner.protocol()

    fn query() String:
        return self.inner.query()

    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]:
        return self.inner.read(max_bytes)

    fn send_headers(status: Int, headers: HttpHeaders) Result[Unit, HttpError]:
        try self.inner.send_headers(status, with_extra(headers, self.extra))
        counted(self.state, status, 0)
        return ok(unit)

    fn send(status: Int, headers: HttpHeaders, body: Bytes) Result[Unit, HttpError]:
        try self.inner.send(status, with_extra(headers, self.extra), body)
        counted(self.state, status, body.length())
        return ok(unit)

    fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) Result[WebSocket, WebSocketError]:
        return self.inner.upgrade(allowed_origins, subprotocols, max_message_bytes)

    fn write(data: String) Result[Unit, IoError]:
        try self.inner.write(data)
        counted(self.state, 0, data.byte_length())
        return ok(unit)

    fn write_bytes(data: Bytes) Result[Unit, IoError]:
        try self.inner.write_bytes(data)
        counted(self.state, 0, data.length())
        return ok(unit)

# Middleware that gives every request an id: the request's own `X-Request-Id` when it is 1 to 128
# printable ASCII characters, otherwise a new UUID. The id is set on the request headers, where
# handlers and later middleware read it, and added to the response as `X-Request-Id`.
export fn request_id() fn(
    HttpExchange,
    fn(HttpExchange) Result[Unit, HttpError]
) Result[Unit, HttpError]:
    return fn exchange, next: with_request_id(exchange, next)

fn with_request_id(
    exchange: HttpExchange,
    next: fn(HttpExchange) Result[Unit, HttpError]
) Result[Unit, HttpError]:
    let request = exchange.headers()
    var id = request.values("X-Request-Id").first().get("")

    if not usable_id(id):
        id = try new_id()
        request.remove("X-Request-Id")
        try request.append("X-Request-Id", id)

    let extra = headers()
    try extra.append("X-Request-Id", id)
    return next(new_tap(exchange, extra))

fn usable_id(id: String) Bool:
    return (
        id.length() >= 1
        and id.length() <= 128
        and id.scalar_values().all(fn c: (c > 32 and c < 127))
    )

fn new_id() Result[String, HttpError]:
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
export fn access_log(
    logger: Logger
) fn(HttpExchange, fn(HttpExchange) Result[Unit, HttpError]) Result[Unit, HttpError]:
    return fn exchange, next: with_access_log(logger, exchange, next)

fn with_access_log(
    logger: Logger,
    exchange: HttpExchange,
    next: fn(HttpExchange) Result[Unit, HttpError]
) Result[Unit, HttpError]:
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

fn answered(status: Int, succeeded: Bool) Int:
    if status != 0: return status
    if succeeded: return 204

    return 500

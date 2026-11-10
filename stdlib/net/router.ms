// Request routing and middleware over `HttpExchange`, implemented in Manuscript.
import (
    Bytes, BytesBuilder from "@std/bytes.ms",
    headers,
    HttpExchange,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    reply,
    text from "@std/net/http.ms",
    NativeWebSocket from "@std/net/websocket.ms",
    Logger from "@std/log.ms",
    uuid_v4 from "@std/data/uuid.ms",
    monotonic from "@std/time.ms",
    Closeable from "@std/core.ms",
    msrt_promise_drop,
    msrt_promise_take,
    msrt_promise_wait,
    msrt_pipe_close_reader,
    msrt_pipe_close_writer,
    msrt_pipe_new,
    msrt_pipe_read,
    msrt_pipe_write from "@std/internal/promises.ms",
)

// A value with one holder at a time, kept in a one-message in-memory pipe whose id is the slot: `take_slot` moves it out
// (waiting while another holder has it) and `put_slot` moves it back. The exchange state below lives in one because
// middleware replaces the exchange with a wrapper of its own type, so the value that comes back from a handler is not
// the one that was handed in; the slot is what both sides can reach.
fn new_slot[T](value: T) Int:
    pipe := msrt_pipe_new(1)
    _first := msrt_pipe_write(pipe, value)
    return pipe

fn take_slot[T](slot: Int) T:
    read := msrt_pipe_read(slot)
    _code := msrt_promise_wait(read, -1)
    value := msrt_promise_take[T](read).get()
    msrt_promise_drop(read)
    return value

fn put_slot[T](slot: Int, value: T) Unit:
    _written := msrt_pipe_write(slot, value)

// Ends the pipe of `slot`; call it once, when the last holder is done.
fn release_slot(slot: Int) Unit:
    msrt_pipe_close_writer(slot)
    msrt_pipe_close_reader(slot)

// The value of a slot while one holder works on it; it returns to the slot when the scope ends, however it ends.
type Held[T]:
    slot: Int
    // One item while held; moving it out through `pop` returns it to the slot.
    items: List[T]
    held: Bool

fn hold[T](slot: Int) Held[T]:
    return Held[T](slot: slot, items: [take_slot[T](slot)], held: true)

impl Closeable for Held[T]:
    var fn close() Unit!:
        if self.held:
            self.held = false
            if value := self.items.pop():
                put_slot(self.slot, value)

// The values a matched pattern captured, by name.
export type RouteParams:
    // Names in pattern order.
    names: List[String]
    // The captured text for each name; a wildcard holds the remaining segments joined by `/`.
    values: List[String]

impl RouteParams:
    // Returns the text captured for `name`, or none when the pattern has no such parameter.
    fn get(name: String) String?:
        if index := self.names.index_of(name): return self.values[index].clone()

        return none

    // Returns the text captured for `name`, or `fallback` when the pattern has no such parameter.
    fn get_or(name: String, fallback: String) String:
        return self.get(name).get(fallback)

// One segment of a route pattern.
export enum Segment:
    // Matches exactly this text.
    Literal(
        // The exact text a request path segment must equal, case-sensitively.
        text: String
    )
    // Matches one nonempty segment and captures it.
    Param(
        // The name `RouteParams.get` finds the captured segment under.
        name: String
    )
    // Matches the rest of the path, possibly nothing, and captures it joined by `/`.
    Rest(
        // The name `RouteParams.get` finds the remaining path under.
        name: String
    )

// A registered route: the method token and pattern it answers, and the handler that runs on a match.
export type Route:
    // The method token the route answers, such as `GET`.
    method: String
    // The pattern text as registered.
    pattern: String
    // The pattern split at `/` into segments, in path order.
    segments: List[Segment]
    // The middleware groups of the routers this route was mounted through, outermost first, as
    // positions in `Router.groups`.
    around: List[Int]
    // Runs when the route matches, with the values the pattern captured.
    handler: fn(var HttpExchange, RouteParams) Unit!

// Routes requests by method and path and wraps them in middleware.
//
// Patterns are `/` followed by literal segments, `:name` parameters that match one segment, and
// a final `*name` that matches the rest of the path (possibly nothing). The first route
// registered that matches wins, and a trailing slash is part of the path.
export type Router:
    // Registered routes in registration order.
    routes: List[Route] = []
    // Middleware in the order it wraps requests: the first one added runs outermost.
    middleware: List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!] = []
    // The middleware of each mounted router, in mount order; a route names the groups around it.
    groups: List[List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!]] = []

impl Router:
    // Registers `handler` for `method` and `pattern`.
    // A route also answers HEAD when `method` is GET and no HEAD route matches. Registering the
    // same method and pattern shape twice returns Duplicate.
    var fn route(
        method: HttpMethod,
        pattern: String,
        handler: fn(var HttpExchange, RouteParams) Unit!
    ) Unit!:
        segments := try parse_pattern(pattern.clone())
        return insert(
            var self.routes,
            Route(
                method: method.text(), pattern: pattern, segments: segments, around: [],
                handler: handler
            )
        )

    // Registers `handler` for GET requests to `pattern`; shorthand for `route(HttpMethod.Get, pattern, handler)`.
    var fn get(pattern: String, handler: fn(var HttpExchange, RouteParams) Unit!) Unit!:
        return self.route(HttpMethod.Get, pattern, handler)

    // Registers `handler` for HEAD requests to `pattern`; shorthand for `route(HttpMethod.Head, pattern, handler)`.
    var fn head(pattern: String, handler: fn(var HttpExchange, RouteParams) Unit!) Unit!:
        return self.route(HttpMethod.Head, pattern, handler)

    // Registers `handler` for POST requests to `pattern`; shorthand for `route(HttpMethod.Post, pattern, handler)`.
    var fn post(pattern: String, handler: fn(var HttpExchange, RouteParams) Unit!) Unit!:
        return self.route(HttpMethod.Post, pattern, handler)

    // Registers `handler` for PUT requests to `pattern`; shorthand for `route(HttpMethod.Put, pattern, handler)`.
    var fn put(pattern: String, handler: fn(var HttpExchange, RouteParams) Unit!) Unit!:
        return self.route(HttpMethod.Put, pattern, handler)

    // Registers `handler` for PATCH requests to `pattern`; shorthand for `route(HttpMethod.Patch, pattern, handler)`.
    var fn patch(
        pattern: String,
        handler: fn(var HttpExchange, RouteParams) Unit!
    ) Unit!:
        return self.route(HttpMethod.Patch, pattern, handler)

    // Registers `handler` for DELETE requests to `pattern`; shorthand for `route(HttpMethod.Delete, pattern, handler)`.
    var fn delete(
        pattern: String,
        handler: fn(var HttpExchange, RouteParams) Unit!
    ) Unit!:
        return self.route(HttpMethod.Delete, pattern, handler)

    // Registers `handler` for OPTIONS requests to `pattern`; shorthand for `route(HttpMethod.Options, pattern, handler)`.
    var fn options(
        pattern: String,
        handler: fn(var HttpExchange, RouteParams) Unit!
    ) Unit!:
        return self.route(HttpMethod.Options, pattern, handler)

    // Moves every route of `routes` under `prefix`, wrapped in that router's own middleware.
    // The prefix is `/` followed by segments with no trailing slash, and it may hold parameters.
    // The mounted router's `/` route answers `prefix` itself. A router holds functions, which
    // have one owner, so `routes` is taken: build it again to mount it elsewhere.
    var fn mount(prefix: String, routes: Router) Unit!:
        if prefix.ends_with("/") and prefix != "/":
            return error(invalid_pattern(prefix))

        var mounted = routes
        base := if prefix == "/": "" else: prefix.clone()
        offset := self.groups.length()
        var groups = drain(var mounted.groups)
        while not groups.is_empty():
            self.groups.append(groups.pop().get())

        own := self.groups.length()
        self.groups.append(in_order(var mounted.middleware))

        var sources = drain(var mounted.routes)

        while not sources.is_empty():
            var route = sources.pop().get()
            try remount(var route, base, own, offset)
            try insert(var self.routes, route)

    // Adds middleware around every route and around the 404, 405 and OPTIONS answers.
    // It receives the exchange and a continuation that runs the rest of the chain with the exchange
    // it is given, so a middleware can pass on a wrapped one (see `request_id` and `access_log`).
    var fn use(middleware: fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!) Unit:
        self.middleware.append(middleware)

    // Returns the function to pass to `serve`; it takes the router, so register every route first.
    // Unmatched paths answer 404, a path matched only under other methods answers 405 with
    // `Allow`, and OPTIONS on a known path answers 204 with `Allow`. `OPTIONS *` answers 204 with
    // the `Allow` of every registered method.
    fn handler() fn(var HttpExchange) Unit!:
        return fn(var exchange: HttpExchange): dispatch(
            self.routes, self.middleware, self.groups, var exchange
        )

// Adds a route unless one with the same method and shape exists.
fn insert(var routes: List[Route], route: Route) Unit!:
    shape := shape_of(route.segments)
    for existing in routes:
        if existing.method == route.method and shape_of(existing.segments) == shape:
            return error(
                Error(
                    "router: duplicate route {route.method} {route.pattern}",
                    kind: "EEXIST",
                    details: {
                        "method": route.method.clone(), "pattern": route.pattern.clone()
                    }
                )
            )
    routes.append(route)

// Rewrites a route moved out of a mounted router: its pattern under `base`, the mounted
// router's middleware group `own` outermost, and its own groups moved up by `offset`.
fn remount(var route: Route, base: String, own: Int, offset: Int) Unit!:
    tail := if route.pattern == "/": "" else: route.pattern.clone()
    pattern := if not (base + tail).is_empty(): base + tail else: "/"
    route.segments = try parse_pattern(pattern.clone())
    route.pattern = pattern

    var around = [own]
    for group in route.around:
        around.append(group + offset)
    route.around = around

// Empties `from` into a new list, last element first; popping the result walks `from` in order.
fn drain[T](var from: List[T]) List[T]:
    var stack: List[T] = []
    while not from.is_empty():
        stack.append(from.pop().get())
    return stack

// Empties `from` into a new list in the same order.
fn in_order[T](var from: List[T]) List[T]:
    var stack = drain(var from)
    return drain(var stack)

fn invalid_pattern(pattern: String) Error:
    return Error(
        "router: invalid pattern {pattern}", kind: "EINVAL",
        details: {"pattern": pattern.clone()}
    )

// Parses `pattern` into segments, rejecting empty or repeated names and a wildcard that is not last.
fn parse_pattern(pattern: String) List[Segment]!:
    if not pattern.starts_with("/"): return error(invalid_pattern(pattern))

    var segments: List[Segment] = []
    var names: List[String] = []
    parts := split_path(pattern)

    for entry in parts.entries():
        segment := segment_of(entry.value)
        last := entry.index == parts.length() - 1
        if not valid_segment(segment, names, last):
            return error(invalid_pattern(pattern))

        if name := segment_name(segment): names.append(name)
        segments.append(segment)

    return ok(segments)

// The segments of an absolute path; "/" has none.
fn split_path(path: String) List[String]:
    if path == "/": return []

    return path.drop(1).split("/")

fn segment_of(part: String) Segment:
    if part.starts_with(":"): return Segment.Param(part.drop(1))
    if part.starts_with("*"): return Segment.Rest(part.drop(1))

    return Segment.Literal(part.clone())

fn segment_name(segment: Segment) String?:
    match segment:
        Literal(_): return none
        Param(name): return name.clone()
        Rest(name): return name.clone()

fn valid_segment(segment: Segment, names: List[String], last: Bool) Bool:
    match segment:
        Literal(text): return not text.is_empty() or last
        Param(name): return not name.is_empty() and not names.contains(name)
        Rest(name): return (last and not name.is_empty() and not names.contains(name))

// Patterns with the same shape match the same paths, whatever their parameter names.
fn shape_of(segments: List[Segment]) String:
    return segments.map(fn segment: shape_text(segment)).join("/")

fn shape_text(segment: Segment) String:
    match segment:
        Literal(text): return "={text}"
        Param(_): return ":"
        Rest(_): return "*"

// What the routes say about one request path.
type Lookup:
    // The matching route for the method, if any.
    found: Int?
    // Captures of that route.
    params: RouteParams
    // Methods that have a route for the path, for `Allow`.
    allow: List[String]

fn lookup(routes: List[Route], method: String, parts: List[String]) Lookup:
    var found: Int? = none
    var fallback = false
    var params = RouteParams(names: [], values: [])
    var allow: List[String] = []
    var index = 0

    while index < routes.length():
        route := routes[index]

        if captured := capture(route.segments, parts):
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

// A GET route also serves HEAD.
fn serves(registered: String, requested: String) Bool:
    return registered == requested or (registered == "GET" and requested == "HEAD")

fn names_of(segments: List[Segment]) List[String]:
    return segments.flat_map(fn segment: name_list(segment))

fn name_list(segment: Segment) List[String]:
    if name := segment_name(segment): return [name]

    return []

// The captured values when `parts` match `segments`.
fn capture(segments: List[Segment], parts: List[String]) List[String]?:
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

// Whether `segment` matches `part`; a parameter adds the text to `values`.
fn accepts(segment: Segment, part: String, var values: List[String]) Bool:
    match segment:
        Literal(text): return text == part
        Param(_):
            if part.is_empty(): return false

            values.append(part.clone())
            return true
        Rest(_): return true

// What `finish` needs from the routes: the matched route and, for `OPTIONS *`, every registered method. Copies of
// the little the request uses, so the continuation handed to middleware owns it.
// Where a request goes: the method, the lookup, and the `Allow` of every route for `OPTIONS *`.
type Target:
    method: String
    found: Lookup
    every: List[String]

// Runs one request through the router's middleware and into `finish`. The continuations borrow
// the routing table: each is called once by the middleware before it and owns nothing.
fn dispatch(
    routes: List[Route],
    middleware: List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!],
    groups: List[List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!]],
    var exchange: HttpExchange
) Unit!:
    method := exchange.method().text()
    found := lookup(routes, method, split_path(exchange.path()))
    var every: List[String] = []
    if method == "OPTIONS" and exchange.path() == "*":
        every = routes.map(fn route: route.method.clone())

    target := Target(method: method, found: found, every: every)
    return chain(
        middleware, 0, var exchange,
        fn(var last: HttpExchange): finish(routes, groups, target, var last)
    )

// Runs `middleware` from `at` on, then `last`.
fn chain(
    middleware: List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!],
    at: Int,
    var exchange: HttpExchange,
    last: fn(var HttpExchange) Unit!
) Unit!:
    if at >= middleware.length(): return last(var exchange)

    return middleware[at](
        var exchange,
        fn(var next: HttpExchange): chain(middleware, at + 1, var next, last)
    )

// Runs the middleware groups `around` from `at` on, then `last`.
fn chain_groups(
    groups: List[List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!]],
    around: List[Int],
    at: Int,
    var exchange: HttpExchange,
    last: fn(var HttpExchange) Unit!
) Unit!:
    if at >= around.length(): return last(var exchange)

    return chain(
        groups[around[at]],
        0,
        var exchange,
        fn(var next: HttpExchange): chain_groups(
            groups, around, at + 1, var next, last
        )
    )

// Runs the matched route, or answers 404, 405 or the OPTIONS listing.
fn finish(
    routes: List[Route],
    groups: List[List[fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!]],
    target: Target,
    var exchange: HttpExchange
) Unit!:
    method := target.method
    found := target.found

    if index := found.found:
        route := routes[index]
        return chain_groups(
            groups,
            route.around,
            0,
            var exchange,
            fn(var last: HttpExchange): route.handler(
                var last, found.params
            )
        )

    if method == "OPTIONS" and exchange.path() == "*":
        var server_wide = text(204, "")
        try server_wide.headers.append("Allow", allow_text(target.every))
        return reply(var exchange, server_wide)

    if found.allow.is_empty(): return reply(var exchange, text(404, "not found\n"))

    var response = text(if method != "OPTIONS": 405 else: 204, "")
    try response.headers.append("Allow", allow_text(found.allow))
    return reply(var exchange, response)

// Methods with a route for the path, sorted and without repeats; GET adds HEAD, and OPTIONS is always answered.
fn allow_text(methods: List[String]) String:
    var all = methods.clone()
    if all.contains("GET"): all.append("HEAD")
    all.append("OPTIONS")
    return all.distinct().sorted().join(", ")

impl Router:
    // Runs `request` through the router without a socket and returns the response it produced.
    // A handler error is returned as is; the server would answer it with a 500. A handler that
    // sends nothing answers 204.
    fn call(request: HttpRequest) HttpResponse!:
        state := new_slot(
            TestState(
                status: 0, sent: false, complete: false, closed: false, head: headers(),
                body: BytesBuilder(), unread: request.body.clone()
            )
        )
        var exchange: HttpExchange = TestExchange(
            request: request.clone(), state: state
        )
        ran := dispatch(self.routes, self.middleware, self.groups, var exchange)
        outcome := finished(state)
        release_slot(state)
        if ran.is_error(): return error(ran.err().clone())

        return outcome

// What an in-process handler has sent so far.
type TestState:
    status: Int
    sent: Bool
    complete: Bool
    closed: Bool
    head: HttpHeaders
    body: BytesBuilder
    unread: Bytes?

type TestExchange:
    request: HttpRequest
    state: Int

fn finished(state: Int) HttpResponse!:
    var guard = hold[TestState](state)
    if not guard.items[0].sent:
        return ok(HttpResponse(status: 204, headers: headers(), body: "".to_bytes()))

    return ok(
        HttpResponse(
            status: guard.items[0].status, headers: guard.items[0].head.clone(),
            body: guard.items[0].body.drain()
        )
    )

impl HttpExchange for TestExchange:
    var fn close() Unit:
        var guard = hold[TestState](self.state)
        guard.items[0].closed = true

    fn headers() HttpHeaders:
        return self.request.headers.clone()

    fn method() HttpMethod:
        return self.request.method.clone()

    fn path() String:
        return self.request.path.clone()

    fn protocol() String:
        return self.request.protocol.clone()

    fn query() String:
        return self.request.query.clone()

    var fn read(max_bytes: Int?) Bytes?!:
        requested := max_bytes.get(65536)
        if requested <= 0: return error(Error("I/O: invalid input", kind: "EINVAL"))

        max := if requested > 65536: 65536 else: requested
        var guard = hold[TestState](self.state)
        if guard.items[0].closed: return error(
            Error("I/O: resource is closed", kind: "EBADF")
        )

        chunk := guard.items[0].unread.clone()
        guard.items[0].unread = none

        if bytes := chunk:
            if bytes.length() == 0: return ok(none)

            n := if max < bytes.length(): max else: bytes.length()
            if n < bytes.length():
                guard.items[0].unread = bytes.slice(n, bytes.length()).get()
            return ok(bytes.slice(0, n).get())

        return ok(none)

    var fn send_headers(status: Int, headers: HttpHeaders) Unit!:
        if status < 200 or status > 599: return error(
            Error("HTTP: invalid input", kind: "EINVAL")
        )
        if headers.contains("Content-Length"): return error(
            Error("HTTP: invalid input", kind: "EINVAL")
        )
        if headers.contains("Transfer-Encoding"): return error(
            Error("HTTP: invalid input", kind: "EINVAL")
        )
        if headers.contains("Connection"): return error(
            Error("HTTP: invalid input", kind: "EINVAL")
        )

        var guard = hold[TestState](self.state)
        if guard.items[0].closed: return error(
            Error("HTTP: resource is closed", kind: "EBADF")
        )
        if guard.items[0].sent: return error(
            Error("HTTP: invalid input", kind: "EINVAL")
        )

        guard.items[0].status = status
        guard.items[0].head = headers.clone()
        guard.items[0].sent = true

    var fn send(status: Int, headers: HttpHeaders, body: Bytes) Unit!:
        try self.send_headers(status, headers)

        var guard = hold[TestState](self.state)
        guard.items[0].complete = true
        if self.request.method.text() == "HEAD" or not has_body(status): return ok(unit)

        guard.items[0].body.append_bytes(body)

    var fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Int?
    ) NativeWebSocket!:
        return error(Error("router: WebSocket upgrades need a server", kind: "ENOTSUP"))

    var fn write(data: String) Unit!:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!:
        var guard = hold[TestState](self.state)
        if guard.items[0].closed: return error(
            Error("I/O: resource is closed", kind: "EBADF")
        )
        if not guard.items[0].sent or guard.items[0].complete: return error(
            Error("I/O: invalid input", kind: "EINVAL")
        )
        if not has_body(guard.items[0].status): return error(
            Error("I/O: invalid input", kind: "EINVAL")
        )
        if self.request.method.text() == "HEAD": return ok(unit)

        guard.items[0].body.append_bytes(data)

// Whether a response with this status may carry a body.
fn has_body(status: Int) Bool:
    return status >= 200 and status != 204 and status != 304

// What a wrapped exchange has sent so far.
type TapState:
    status: Int
    bytes: Int

// An exchange that passes everything to `inner`, adds `extra` to the headers of its response, and counts the status and body bytes sent.
type Tap:
    inner: HttpExchange
    extra: HttpHeaders
    request: HttpHeaders
    state: Int?

// `state` is a slot counting what is sent, which the caller made and reads afterwards.
fn new_tap(
    inner: HttpExchange,
    extra: HttpHeaders,
    request: HttpHeaders,
    state: Int? = none
) Tap:
    return Tap(inner: inner, extra: extra, request: request, state: state)

// Replaces `exchange` with one whose `headers()` reports `request` and everything else passes through.
// Middleware uses it to hand later layers changed request headers, since a received header set is a copy.
export fn with_request_headers(var exchange: HttpExchange, request: HttpHeaders) Unit:
    exchange = new_tap(exchange, headers(), request)

fn counted(slot: Int?, status: Int, bytes: Int) Unit:
    if state := slot:
        var guard = hold[TapState](state)
        if status != 0: guard.items[0].status = status
        guard.items[0].bytes += bytes

fn snapshot(state: Int) TapState:
    var guard = hold[TapState](state)
    return TapState(status: guard.items[0].status, bytes: guard.items[0].bytes)

// `sent` plus the `extra` headers it does not already have.
fn with_extra(sent: HttpHeaders, extra: HttpHeaders) HttpHeaders:
    var all = sent.clone()
    for name in extra.names():
        if not all.contains(name):
            for value in extra.values(name):
                all.append(name, value).get(unit)
    return all

impl Tap:
    // The body bytes the exchange transmits: none for HEAD or a status that forbids a body.
    fn sent_length(status: Int, length: Int) Int:
        if self.inner.method() == HttpMethod.Head or not has_body(status): return 0

        return length

    // The status the response headers went out with, or 200 before any are sent.
    fn status_so_far() Int:
        if state := self.state:
            seen := snapshot(state).status
            if seen != 0: return seen

        return 200

impl HttpExchange for Tap:
    var fn close() Unit:
        self.inner.close()

    fn headers() HttpHeaders:
        return self.request.clone()

    fn method() HttpMethod:
        return self.inner.method()

    fn path() String:
        return self.inner.path()

    fn protocol() String:
        return self.inner.protocol()

    fn query() String:
        return self.inner.query()

    var fn read(max_bytes: Int?) Bytes?!:
        return self.inner.read(max_bytes)

    var fn send_headers(status: Int, headers: HttpHeaders) Unit!:
        try self.inner.send_headers(status, with_extra(headers, self.extra))
        counted(self.state, status, 0)

    var fn send(status: Int, headers: HttpHeaders, body: Bytes) Unit!:
        try self.inner.send(status, with_extra(headers, self.extra), body)
        counted(self.state, status, self.sent_length(status, body.length()))

    var fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Int?
    ) NativeWebSocket!:
        return self.inner.upgrade(allowed_origins, subprotocols, max_message_bytes)

    var fn write(data: String) Unit!:
        try self.inner.write(data)
        counted(
            self.state, 0, self.sent_length(self.status_so_far(), data.byte_length())
        )

    var fn write_bytes(data: Bytes) Unit!:
        try self.inner.write_bytes(data)
        counted(self.state, 0, self.sent_length(self.status_so_far(), data.length()))

// Middleware that gives every request an id: the request's own `X-Request-Id` when it is 1 to 128
// printable ASCII characters, otherwise a new UUID. The id is set on the request headers the wrapped exchange reports, where
// handlers and later middleware read it, and added to the response as `X-Request-Id`.
export fn request_id() fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!:
    return fn(var exchange: HttpExchange, next: fn(var HttpExchange) Unit!): with_request_id(
        var exchange, next
    )

fn with_request_id(var exchange: HttpExchange, next: fn(var HttpExchange) Unit!) Unit!:
    var request = exchange.headers()
    var id = request.values("X-Request-Id").first().get("")

    if not usable_id(id):
        id = try new_id()
        request.remove("X-Request-Id")
        try request.append("X-Request-Id", id)

    var extra = headers()
    try extra.append("X-Request-Id", id)
    exchange = new_tap(exchange, extra, request)
    return next(var exchange)

fn usable_id(id: String) Bool:
    return (
        id.length() >= 1
        and id.length() <= 128
        and id.scalar_values().all(fn c: (c > 32 and c < 127))
    )

fn new_id() String!:
    made := uuid_v4()
    if made.is_error(): return error(Error(made.err().message.clone(), kind: "EIO"))

    return ok(made.get().clone())

// One request as `access_log` writes it.
type AccessEntry:
    method: String
    path: String
    protocol: String
    status: Int
    bytes: Int
    duration_ms: Int

// Middleware that writes one Info record named `request` to `logger` after each request, with
// the method, path, protocol, response status, body bytes written and duration in milliseconds.
// A handler that sends nothing is logged as 204 and one that fails before sending as 500. A
// logging failure never fails the request.
export fn access_log(
    logger: Logger
) fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!:
    return fn(var exchange: HttpExchange, next: fn(var HttpExchange) Unit!): with_access_log(
        logger, var exchange, next
    )

fn with_access_log(
    logger: Logger,
    var exchange: HttpExchange,
    next: fn(var HttpExchange) Unit!
) Unit!:
    started := monotonic()
    method := exchange.method().text()
    path := exchange.path()
    protocol := exchange.protocol()
    request := exchange.headers()
    state := new_slot(TapState(status: 0, bytes: 0))
    exchange = new_tap(exchange, headers(), request, state)

    result := next(var exchange)
    sent := snapshot(state)
    release_slot(state)

    status := answered(sent.status, result.is_ok())
    entry := AccessEntry(
        method: method, path: path, protocol: protocol, status: status,
        bytes: sent.bytes,
        duration_ms: monotonic().difference(started).to_milliseconds()
    )
    logged := logger.info("request", entry)
    return result

fn answered(status: Int, succeeded: Bool) Int:
    if status != 0: return status
    if succeeded: return 204

    return 500

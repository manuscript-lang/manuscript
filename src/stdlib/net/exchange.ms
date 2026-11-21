import (
	Bytes from "@std/bytes.ms",
	HttpExchange, HttpHeaders, HttpMethod, headers from "@std/net/http.ms",
	decode_component from "@std/net/url.ms",
	WebSocket, web_socket_from from "@std/net/websocket.ms",

	msstd_xchg_finish,
	msstd_xchg_headers,
	msstd_xchg_method,
	msstd_xchg_protocol,
	msstd_xchg_read,
	msstd_xchg_reset,
	msstd_xchg_send_head,
	msstd_xchg_share,
	msstd_xchg_take_conn,
	msstd_xchg_target,
	msstd_xchg_write from "@std/internal/http.ms",
	msstd_ws_handshake, msstd_ws_serve from "@std/internal/net.ms",
)

// One HTTP/1 server exchange as the runtime hands it over: the request head, the body
// framing and the response framing live behind this handle
// (src/runtime/include/ms_rt/xchg.h). The connection loop keeps one handle for
// `finish_exchange`; the handler's
// `HttpExchange` owns another.
export extern type NativeExchange

// The largest piece `read` returns, whatever the caller asks for.
READ_CHUNK := 65536
// How much of a request body the loop reads and drops so a handler that ignored it does
// not cost the connection.
DRAIN_LIMIT := 262144

// The per-request limits an exchange enforces for its handler; none sets no cap.
export type ExchangeLimits:
	// Largest request body in bytes; reading past it returns EOVERFLOW.
	max_body_bytes: Int? = none
	// Most response body bytes a handler may write; writing past it returns EOVERFLOW.
	max_response_bytes: Int? = none
	// Largest response header block in bytes.
	max_header_bytes: Int? = none
	// Whether the connection is TLS, which the WebSocket origin check compares against.
	secure: Bool = false

// A request target split into the routable path and the raw query.
export type RequestTarget:
	// The percent-decoded path with dot segments resolved; it never climbs above the
	// root. `*` stays as written.
	path: String
	// The raw query without the leading `?`, empty when there is none.
	query: String
	// The authority of an absolute-form target (`GET http://host/p`), which replaces
	// the
	// `Host` field.
	host: String?

fn bad_target(reason: String) Error:
	return Error(f"http: {reason}", kind: "EINVAL")

// Whether `value` can be a `Host` or `:authority` value: a registered name, IPv4 or
// bracketed IPv6 literal with an optional port. Userinfo, spaces, path delimiters and
// non-ASCII bytes are refused; the empty value is valid.
fn valid_authority(value: String) Bool:
	punctuation := "-._~%!$&'()*+,;=:[]".to_bytes()
	text := value.to_bytes()

	for i in 0..text.length():
		c := text.get(i)
		n := c.to_int()
		alnum := (
			(n >= 48 and n <= 57)
			or (n >= 65 and n <= 90)
			or (n >= 97 and n <= 122)
		)
		if alnum or punctuation.index_of_byte(c, 0).is_some(): continue

		return false

	return true

// Resolves `.` and `..` and collapses empty segments in a rooted path, keeping a
// trailing slash; the result never climbs above the root.
fn clean_path(path: String) String:
	var stack: List[String] = []

	for segment in path.split("/"):
		if segment == "" or segment == ".": continue

		if segment == "..":
			if stack.length() > 0: stack.pop()
			continue

		stack.append(segment.clone())

	out := "/" + stack.join("/")
	if path.ends_with("/") and out != "/": return out + "/"

	return out

// Splits and normalizes the target of a request line. A target with a control byte or
// space, a malformed escape, invalid UTF-8, or an encoded slash or NUL in its path
// returns EINVAL, which the connection loop answers with 400.
export fn parse_target(raw: String) RequestTarget!:
	text := raw.to_bytes()

	for i in 0..text.length():
		n := text.get(i).to_int()
		if n < 32 or n == 127: return error(bad_target("bad request"))

	if raw.contains(" "): return error(bad_target("bad request"))

	var host: String? = none
	var rest = raw.clone()

	if after := raw.cut_prefix("http://"):
		rest = after
	else if after := raw.cut_prefix("https://"):
		rest = after

	if rest.length() != raw.length():
		end := rest.index_any("/?").get_or(rest.length())
		authority := rest.slice(0, end)
		if not valid_authority(authority): return error(bad_target("invalid Host"))

		host = authority
		rest = rest.slice(end, rest.length())

	if cut := rest.split_once("#"): rest = cut.before

	var raw_path = rest.clone()
	var query = ""

	if cut := rest.split_once("?"):
		raw_path = cut.before
		query = cut.after

	if raw_path == "" and host.is_some(): raw_path = "/"
	if raw_path == "*": return ok(RequestTarget(path: "*", query: query, host: host))

	attempt := decode_component(raw_path)
	if attempt.is_error(): return error(bad_target("bad request"))

	decoded := attempt.get()
	if query.to_bytes().decode_utf8().is_none(): return error(
		bad_target("invalid UTF-8 URL")
	)

	lower := raw_path.lower()
	if lower.contains("%00") or lower.contains("%2f") or decoded.contains("\u{0}"):
		return error(bad_target("invalid request path"))
	if decoded.starts_with("/"):
		return ok(RequestTarget(path: clean_path(decoded), query: query, host: host))

	return ok(RequestTarget(path: decoded, query: query, host: host))

fn method_of(text: String) HttpMethod:
	match text:
		"GET": return HttpMethod.Get
		"HEAD": return HttpMethod.Head
		"POST": return HttpMethod.Post
		"PUT": return HttpMethod.Put
		"PATCH": return HttpMethod.Patch
		"DELETE": return HttpMethod.Delete
		"CONNECT": return HttpMethod.Connect
		"OPTIONS": return HttpMethod.Options
		"TRACE": return HttpMethod.Trace
		_: return HttpMethod.Custom(text)

fn closed_error() Error:
	return Error("http: exchange closed", kind: "EBADF")

fn invalid(reason: String) Error:
	return Error(f"http: {reason}", kind: "EINVAL")

fn overflow(reason: String) Error:
	return Error(f"http: {reason}", kind: "EOVERFLOW")

fn websocket_failure(reason: String) Error:
	return Error(reason, kind: "EIO")

fn status_reason(status: Int) String:
	match status:
		400: return "Bad Request"
		403: return "Forbidden"
		405: return "Method Not Allowed"
		426: return "Upgrade Required"
		_: return "Error"

// What the handler sees of one request: the `HttpExchange` over a native exchange.
type ServerExchange:
	// The handler's handle on the exchange.
	native: NativeExchange
	limits: ExchangeLimits
	method_text: String
	target: RequestTarget
	protocol_text: String
	// Request body bytes handed to the handler so far.
	received: Int = 0
	// Response body bytes written so far.
	written: Int = 0
	// The status of the response head, 0 until one is sent.
	status: Int = 0
	// Whether the whole response went out in one `send`, which forbids later writes.
	complete: Bool = false
	closed: Bool = false

fn ServerExchange.no_body_status() Bool:
	return self.status == 204 or self.status == 304

fn ServerExchange.is_head() Bool:
	return self.method_text == "HEAD"

// Ends the exchange; later operations return EBADF. The connection loop finishes the
// response.
fn var ServerExchange.close() Void:
	self.closed = true

// Returns the request headers as an owned copy, repeated values kept apart. An
// absolute-form target replaces `Host`, and `Transfer-Encoding`, which the runtime
// consumed, is dropped.
fn ServerExchange.headers() HttpHeaders:
	var fields = msstd_xchg_headers(self.native)
	fields.remove("Transfer-Encoding")

	if host := self.target.host:
		fields.remove("Host")
		void fields.append("Host", host)

	return fields

fn ServerExchange.method() HttpMethod:
	return method_of(self.method_text.clone())

fn ServerExchange.path() String:
	return self.target.path.clone()

fn ServerExchange.protocol() String:
	return self.protocol_text.clone()

fn ServerExchange.query() String:
	return self.target.query.clone()

// Returns the next piece of the request body, none at its end. Reading past the body
// limit returns EOVERFLOW, and a non-positive `max_bytes` returns EINVAL.
fn var ServerExchange.read(max_bytes: Int?) Bytes?!:
	if self.closed: return error(closed_error())

	var want = READ_CHUNK

	if given := max_bytes:
		if given <= 0: return error(invalid("max_bytes must be positive"))

		if given < want: want = given

	// One byte past the limit is enough to tell that the body is longer.
	var ask = want

	if cap := self.limits.max_body_bytes:
		room := cap - self.received
		if room + 1 < ask: ask = room + 1

	chunk := msstd_xchg_read(self.native, ask, none)?

	if piece := chunk:
		self.received += piece.length()
		if cap := self.limits.max_body_bytes:
			if self.received > cap: return error(
				Error(
					"http: request body is over the limit",
					kind: "EOVERFLOW",
					details: {"limit": "request"},
				)
			)
		return ok(piece)

	return ok(none)

// The response head is checked here once, so a bad head never reaches the wire.
fn ServerExchange.check_head(status: Int, fields: HttpHeaders) Void!:
	if self.closed: return error(closed_error())
	if self.status != 0: return error(invalid("headers already sent"))
	if status < 200 or status > 599: return error(
		invalid("status must be 200 through 599")
	)

	var size = 0

	for name in fields.names():
		lower := name.lower()
		if (
			lower == "content-length"
			or lower == "transfer-encoding"
			or lower == "connection"
		):
			return error(invalid(f"{name} is set by the server"))

		size += name.length() + 4
		for value in fields.get_all_bytes(name).get_or([]):
			size += value.length()

	if cap := self.limits.max_header_bytes:
		if size > cap: return error(overflow("response headers are over the limit"))
	return ok()

fn var ServerExchange.send(status: Int, headers: HttpHeaders, body: Bytes) Void!:
	self.check_head(status, headers)?
	if cap := self.limits.max_response_bytes:
		if body.length() > cap: return error(
			overflow("response body is over the limit")
		)

	empty := status == 204 or status == 304
	var length = body.length()
	if empty: length = 0
	msstd_xchg_send_head(self.native, status, headers, length, none)?
	self.status = status
	self.complete = true
	if empty or self.is_head() or body.is_empty(): return ok()

	msstd_xchg_write(self.native, body, none)?
	self.written = body.length()
	return ok()

fn var ServerExchange.send_headers(status: Int, headers: HttpHeaders) Void!:
	self.check_head(status, headers)?

	var length: Int? = none
	if status == 204 or status == 304: length = 0
	msstd_xchg_send_head(self.native, status, headers, length, none)?
	self.status = status

fn var ServerExchange.write_bytes(move data: Bytes) Void!:
	if self.closed: return error(closed_error())
	if self.status == 0: return error(invalid("send_headers must come first"))
	if self.complete: return error(invalid("the response is already complete"))
	if self.no_body_status(): return error(invalid(f"status {self.status} has no body"))
	if self.is_head(): return ok()

	if cap := self.limits.max_response_bytes:
		if self.written + data.length() > cap: return error(
			overflow("response body is over the limit")
		)
	msstd_xchg_write(self.native, data, none)?
	self.written += data.length()
	return ok()

fn var ServerExchange.write(move data: String) Void!:
	return self.write_bytes(data.to_bytes())

// Answers a refused upgrade with its status line, the version the server speaks and a
// short text body, and closes the connection after it.
fn var ServerExchange.refuse_upgrade(status: Int, reason: String) Error:
	var fields = headers()
	void fields.append("Content-Type", "text/plain; charset=utf-8")
	void fields.append("Sec-Websocket-Version", "13")
	void fields.append("X-Content-Type-Options", "nosniff")
	void fields.append("Connection", "close")

	body := f"{status_reason(status)}\n".to_bytes()
	void msstd_xchg_send_head(self.native, status, fields, body.length(), none)
	void msstd_xchg_write(self.native, body, none)
	self.status = status
	self.complete = true
	return websocket_failure(reason)

// Switches the connection to a WebSocket: the handshake is checked, the 101 head sent,
// and the connection handed to a session that lives until it is closed.
fn var ServerExchange.upgrade(
	allowed_origins: List[String] = [],
	subprotocols: List[String] = [],
	max_message_bytes: Int? = none,
) WebSocket!:
	if self.closed: return error(closed_error())
	if self.status != 0: return error(invalid("headers already sent"))

	if given := max_message_bytes:
		if given <= 0: return error(invalid("max_message_bytes must be positive"))

	request := self.headers()
	var response = headers()
	host := request.get("Host").get_or("")
	shake := msstd_ws_handshake(
		self.method_text,
		host,
		self.limits.secure,
		request,
		allowed_origins,
		subprotocols,
		response,
	)?

	// An upgrade is HTTP/1 only: a request that is not a handshake is reported as such,
	// and an acceptable one over HTTP/2 is refused.
	if self.protocol_text == "HTTP/2.0" or self.protocol_text == "HTTP/2":
		if shake.status != 101: return error(websocket_failure(shake.reason))
		return error(invalid("WebSocket upgrade needs HTTP/1.1"))

	// RFC 6455 section 4.2.1: the opening handshake is an HTTP/1.1 (or later) request.
	if self.protocol_text == "HTTP/1.0":
		return error(self.refuse_upgrade(400, "websocket: upgrade needs HTTP/1.1"))
	if shake.status != 101: return error(
		self.refuse_upgrade(shake.status, shake.reason)
	)

	msstd_xchg_send_head(self.native, 101, response, none, none)?
	self.status = 101
	self.complete = true

	connection := msstd_xchg_take_conn(self.native)?
	native := msstd_ws_serve(connection, shake.subprotocol, max_message_bytes)?
	return ok(web_socket_from(native))

// Reads the head of `native` into the exchange a handler receives. A target that cannot
// be routed returns EINVAL for the connection loop to answer with 400.
export fn open_exchange(
	native: NativeExchange,
	limits: ExchangeLimits = ExchangeLimits(),
) HttpExchange!:
	target := parse_target(msstd_xchg_target(native))?
	return ok(
		ServerExchange(
			native: msstd_xchg_share(native),
			limits: limits,
			method_text: msstd_xchg_method(native),
			target: target,
			protocol_text: msstd_xchg_protocol(native),
		)
	)

// Ends the response after the handler returned `failure` (none on success) and reports
// whether the connection can carry another request. A handler that failed before any
// head went out is answered 413 when its body read ran over the limit and 500
// otherwise; a handler that returned without a response gets 500. A failed handler, or
// any error finishing, closes the connection.
export fn finish_exchange(native: NativeExchange, failure: Error?) Bool:
	if error_found := failure:
		var status = 500

		// Only a request body over its limit is the client's fault; a response over
		// its limit is the handler's.
		if (
			error_found.kind == "EOVERFLOW"
			and error_found.details.get("limit") == "request"
		): status = 413
		void msstd_xchg_send_head(native, status, headers(), 0, none)
		void msstd_xchg_finish(native, none)
		return false

	if msstd_xchg_reset(native, DRAIN_LIMIT, none).is_error(): return false

	keep := msstd_xchg_finish(native, none)
	if found := keep.to_optional(): return found

	// No response went out: answer 500 and close.
	void msstd_xchg_send_head(native, 500, headers(), 0, none)
	void msstd_xchg_finish(native, none)
	return false

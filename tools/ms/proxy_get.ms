// An HTTPS GET through an HTTP proxy (`HTTPS_PROXY`), for toolchain.ms: the stdlib
// client never uses a proxy (it would resolve names itself and bypass the address
// filter), and a build host behind one has no other way out. The tunnel is
// `CONNECT host:port`, then TLS to the real host over it, so the proxy sees no request and TLS verifies the host as usual.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	base64_encode from "@std/data/encoding.ms",
	Connection, connect, start_tls from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	seconds from "@std/time.ms",
)

MAX_REDIRECTS := 5
MAX_HEAD := 65536

// The proxy: `host:port` to connect to and the `Proxy-Authorization` value (empty when
// the URL has no credentials).
export type Proxy:
	address: String
	authorization: String

// `http://[user:password@]host:port`.
export fn parse_proxy(text: String) Proxy!:
	var rest = text.trim()
	if rest.starts_with("http://"): rest = rest.slice(7, rest.length())
	if rest.ends_with("/"): rest = rest.slice(0, rest.length() - 1)

	var authorization = ""

	if at := rest.last_index_of("@"):
		authorization = f"Basic {base64_encode(rest.slice(0, at).to_bytes())}"
		rest = rest.slice(at + 1, rest.length())

	if rest == "" or rest.contains("/"):
		return error(
			Error(
				f"proxy {text} is not http://[user:password@]host:port",
				kind: "EINVAL",
			)
		)

	if not rest.contains(":"): rest = f"{rest}:80"
	return ok(Proxy(address: rest.clone(), authorization: authorization))

// An `https://host[:port]/path` URL.
export type Target:
	host: String
	port: Int
	path: String

export fn parse_https(url: String) Target!:
	if not url.starts_with("https://"):
		return error(Error(f"{url} is not an https URL", kind: "EINVAL"))

	rest := url.slice(8, url.length())
	var authority = rest.clone()
	var path = "/"

	if slash := rest.index_of("/"):
		authority = rest.slice(0, slash)
		path = rest.slice(slash, rest.length())

	var host = authority.clone()
	var port = 443

	if colon := authority.last_index_of(":"):
		host = authority.slice(0, colon)
		port = authority.slice(colon + 1, authority.length()).parse_int().get_or(0)

	if host == "" or port <= 0: return error(
		Error(f"{url} has no host", kind: "EINVAL")
	)

	return ok(Target(host: host.clone(), port: port, path: path.clone()))

// Whether `host` is excluded from the proxy by the `NO_PROXY` list: `*`, or a name or
// domain suffix in it.
export fn bypasses(no_proxy: String, host: String) Bool:
	for entry in no_proxy.split(","):
		name := entry.trim()
		if name == "": continue
		if name == "*" or host == name: return true

		suffix := if name.starts_with("."): name.clone() else: f".{name}"
		if host.ends_with(suffix): return true

	return false

// The proxy that applies to `host` in `env`, or none: `HTTPS_PROXY` (or `https_proxy`),
// unless `NO_PROXY` excludes it.
export fn proxy_for(env: Map[String, String], host: String) String?:
	var proxy = env.get("HTTPS_PROXY").get_or("")
	if proxy == "": proxy = env.get("https_proxy").get_or("")
	if proxy == "": return none

	var no_proxy = env.get("NO_PROXY").get_or("")
	if no_proxy == "": no_proxy = env.get("no_proxy").get_or("")
	if bypasses(no_proxy, host): return none

	return proxy.clone()

// The status line and headers of a response: the status, `Location`, and how the body
// is framed.
export type Head:
	status: Int
	location: String
	chunked: Bool
	length: Int?

export fn parse_head(text: String) Head!:
	lines := text.split("\r\n")
	parts := lines[0].split(" ")
	if parts.length() < 2 or not parts[0].starts_with("HTTP/"):
		return error(Error(f"malformed response: {lines[0]}", kind: "EBADMSG"))

	var head = Head(
		status: parts[1].parse_int().get_or(0),
		location: "",
		chunked: false,
		length: none,
	)

	for line in lines.slice(1, lines.length())?:
		colon := line.index_of(":")
		if colon.is_none(): continue

		name := line.slice(0, colon.get()).trim().lower()
		value := line.slice(colon.get() + 1, line.length()).trim()
		if name == "location": head.location = value.clone()
		if name == "content-length": head.length = value.parse_int()
		if name == "transfer-encoding" and value.lower().contains("chunked"): head.chunked = true

	if head.status == 0: return error(
		Error(f"malformed response: {lines[0]}", kind: "EBADMSG")
	)

	return ok(head)

fn hex_value(text: String) Int!:
	digits := "0123456789abcdef"
	var value = 0

	for c in text.lower().chars():
		at := digits.index_of(c)
		if at.is_none(): return error(Error(f"bad chunk size {text}", kind: "EBADMSG"))

		value = value * 16 + at.get()

	return ok(value)

// The payload of a chunked body.
export fn dechunk(body: Bytes) Bytes!:
	var out = BytesBuilder()
	var at = 0

	while true:
		rest := body.view(at, body.length())
		line_end := rest.index_of("\r\n".to_bytes())
		if line_end.is_none(): return error(
			Error("truncated chunked body", kind: "EBADMSG")
		)

		size_text := rest.slice(0, line_end.get())?.decode_utf8().get_or("")
		size := hex_value(size_text.split(";")[0].trim())?
		at = at + line_end.get() + 2
		if size == 0: return ok(out.build())
		if at + size > body.length(): return error(
			Error("truncated chunked body", kind: "EBADMSG")
		)

		out.append_bytes(body.view(at, at + size))
		at = at + size + 2

	return ok(out.build())

// Opens the tunnel to `target` through `proxy` and runs TLS over it.
fn tunnel(proxy: Proxy, target: Target) Connection!:
	var plain = connect(proxy.address.clone(), timeout: seconds(30)).wait()?
	authority := f"{target.host}:{target.port}"
	var request = f"CONNECT {authority} HTTP/1.1\r\nHost: {authority}\r\n"
	if proxy.authorization != "": request = f"{request}Proxy-Authorization: {proxy.authorization}\r\n"
	plain.output.write(f"{request}\r\n".to_bytes())?

	var seen = "".to_bytes()

	while true:
		chunk := plain.input.next(seconds(30))?
		if chunk.is_none(): return error(
			Error("the proxy closed the connection", kind: "ECONNRESET")
		)

		seen = seen.concat(chunk.get())
		if seen.contains("\r\n\r\n".to_bytes()): break
		if seen.length() > MAX_HEAD: return error(
			Error("the proxy's reply is too long", kind: "EOVERFLOW")
		)

	head := parse_head(seen.decode_utf8().get_or(""))?
	if head.status != 200:
		return error(
			Error(
				f"the proxy refused CONNECT {authority}: status {head.status}",
				kind: "ECONNREFUSED",
			)
		)

	return start_tls(plain, TlsOptions(server_name: target.host.clone()), seconds(30))

// The body of the https `url` fetched through `proxy_url`, following redirects.
export fn proxy_get(proxy_url: String, url: String, max_bytes: Int) Bytes!:
	proxy := parse_proxy(proxy_url)?
	var current = url.clone()

	for hop in 0..MAX_REDIRECTS + 1:
		target := parse_https(current)?
		var connection = tunnel(proxy.clone(), target.clone())?
		request := f"GET {target.path} HTTP/1.1\r\nHost: {target.host}\r\nAccept-Encoding: identity\r\nConnection: close\r\nUser-Agent: ms\r\n\r\n"
		connection.output.write(request.to_bytes())?

		var received = BytesBuilder()
		var total = 0

		while true:
			chunk := connection.input.next(seconds(120))?
			if chunk.is_none(): break

			total += chunk.get().length()
			if total > max_bytes + MAX_HEAD: return error(
				Error(
					f"{current}: the response is too large",
					kind: "EOVERFLOW",
				)
			)

			received.append_bytes(chunk.get())

		raw := received.build()
		end := raw.index_of("\r\n\r\n".to_bytes())
		if end.is_none(): return error(
			Error(
				f"{current}: the response has no end of headers",
				kind: "EBADMSG",
			)
		)

		head := parse_head(raw.slice(0, end.get())?.decode_utf8().get_or(""))?

		if head.status >= 300 and head.status < 400 and head.location != "":
			current = if head.location.starts_with("/"): f"https://{target.host}{head.location}" else: head.location.clone()
			continue

		if head.status != 200: return error(
			Error(
				f"download of {current} answered {head.status}",
				kind: "EIO",
			)
		)

		body := raw.slice(end.get() + 4, raw.length())?
		if head.chunked: return dechunk(body)

		if wanted := head.length:
			if body.length() < wanted: return error(
				Error(
					f"{current}: the body is cut short",
					kind: "ECONNRESET",
				)
			)
			return ok(body.slice(0, wanted)?)

		return ok(body)

	return error(Error(f"{url}: too many redirects", kind: "ELOOP"))

test "parse_proxy reads the address and credentials":
	plain := parse_proxy("http://127.0.0.1:3128/")?
	expect_equal(plain.address, "127.0.0.1:3128")?
	expect_equal(plain.authorization, "")?

	signed := parse_proxy("http://user:pw@proxy.example:8080")?
	expect_equal(signed.address, "proxy.example:8080")?
	expect_equal(signed.authorization, "Basic dXNlcjpwdw==")?
	expect_equal(parse_proxy("http://proxy.example")?.address, "proxy.example:80")?
	expect_true(parse_proxy("socks5://x/y").is_error())?

test "parse_https splits host, port and path":
	plain := parse_https("https://github.com/a/b.tar.gz")?
	expect_equal(plain.host, "github.com")?
	expect_equal(plain.port, 443)?
	expect_equal(plain.path, "/a/b.tar.gz")?

	custom := parse_https("https://h.example:8443")?
	expect_equal(custom.port, 8443)?
	expect_equal(custom.path, "/")?
	expect_true(parse_https("http://x/").is_error())?

test "NO_PROXY excludes hosts and domains":
	expect_true(bypasses("localhost, .internal", "api.internal"))?
	expect_true(bypasses("github.com", "github.com"))?
	expect_true(bypasses("*", "any.example"))?
	expect_true(not bypasses("github.com", "evilgithub.com"))?

	env := {"HTTPS_PROXY": "http://p:1", "NO_PROXY": "github.com"}
	expect_true(proxy_for(env, "objects.example").is_some())?
	expect_true(proxy_for(env, "github.com").is_none())?
	expect_true(proxy_for({"HTTP_PROXY": "http://p:1"}, "x.example").is_none())?

test "parse_head reads status, redirect and framing":
	head := parse_head(
		"HTTP/1.1 302 Found\r\nLocation: https://x.example/f\r\nContent-Length: 12\r\nTransfer-Encoding: chunked"
	)?
	expect_equal(head.status, 302)?
	expect_equal(head.location, "https://x.example/f")?
	expect_equal(head.length.get_or(0), 12)?
	expect_true(head.chunked)?
	expect_true(parse_head("garbage").is_error())?

test "dechunk joins the chunks":
	body := "4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n".to_bytes()
	expect_equal(dechunk(body)?.decode_utf8().get(), "Wikipedia")?
	expect_true(dechunk("4\r\nWi".to_bytes()).is_error())?

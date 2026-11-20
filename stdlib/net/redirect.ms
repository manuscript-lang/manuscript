import (
	HttpHeaders, headers from "@std/net/http.ms",
	parse_ip from "@std/net/ip.ms",
	Url from "@std/net/url.ms",
)

// Redirect policy of the HTTP client. The C client makes one exchange per call, so these
// functions decide whether a response redirects, where it goes, and which request headers
// survive the hop. They follow Go's `net/http` client.

// Returns the method of the follow-up request for a redirect status, or none when the
// status does not redirect. 301, 302 and 303 become GET (HEAD stays HEAD) and drop the
// body; 307 and 308 keep the method and the body.
export fn redirect_method(status: Int, method: String) String?:
	if status >= 301 and status <= 303:
		if method == "HEAD": return "HEAD"
		return "GET"
	if status == 307 or status == 308: return method
	return none

// Reports whether the redirect keeps the request body: only 307 and 308 do.
export fn redirect_keeps_body(status: Int) Bool:
	return status == 307 or status == 308

// Checks a redirect against the client's limits. `followed` counts the redirects already
// followed, `host_allowed` is the network restriction on the new host, and `max_redirects`
// is the cap (none for no cap). A redirect from HTTPS to HTTP is refused.
export fn check_redirect(
	followed: Int,
	from: Url,
	to: Url,
	host_allowed: Bool,
	max_redirects: Int? = none,
) Void!:
	if cap := max_redirects:
		if followed >= cap: return error(Error("redirect limit exceeded", kind: "EIO"))
	if from.scheme == "https" and to.scheme != "https":
		return error(Error("TLS downgrade redirect rejected", kind: "EIO"))
	if not host_allowed:
		return error(Error("network policy denied redirect", kind: "EIO"))
	return ok()

// Reports whether two URLs share scheme, host and written port.
export fn same_origin(a: Url, b: Url) Bool:
	return a.scheme == b.scheme and a.host == b.host and a.port == b.port

// Reports whether `sub` is `parent` or a subdomain of it. An IP literal only matches
// itself.
export fn is_domain_or_subdomain(sub: String, parent: String) Bool:
	s := sub.lower()
	p := parent.lower()
	if s == p: return true
	if is_ip_literal(s) or is_ip_literal(p): return false
	return s.ends_with("." + p)

fn is_ip_literal(host: String) Bool:
	return parse_ip(host).is_ok()

// Returns the `Referer` of a redirected request, or none. It is none when the redirect
// leaves HTTPS for HTTP or crosses origins, since the last URL's query can carry secrets.
// A non-empty `Referer` the caller set explicitly is kept.
export fn referer_for(last: Url, next: Url, initial: HttpHeaders, last_text: String) String?:
	if last.scheme == "https" and next.scheme != "https": return none
	if explicit := initial.get("Referer"):
		if not explicit.is_empty(): return explicit
	if not same_origin(last, next): return none
	return last_text

fn is_entity_header(name: String) Bool:
	return (
		name.equal_fold("Content-Type")
		or name.equal_fold("Content-Encoding")
		or name.equal_fold("Content-Language")
		or name.equal_fold("Content-Location")
	)

fn is_credential(name: String) Bool:
	return (
		name.equal_fold("Authorization")
		or name.equal_fold("Www-Authenticate")
		or name.equal_fold("Cookie")
		or name.equal_fold("Cookie2")
	)

fn is_origin_credential(name: String) Bool:
	return (
		name.equal_fold("Authorization")
		or name.equal_fold("Cookie")
		or name.equal_fold("Proxy-Authorization")
	)

// Returns the headers of a redirected request: `initial` minus the credentials that must
// not leave the origin and, when the body is dropped, the headers that describe it.
// Authorization and cookie headers go only to the same host or a subdomain of the
// previous hop's host, and Authorization, Cookie and Proxy-Authorization only within one
// origin. `previous` is the URL of the hop before `old`.
export fn redirect_headers(
	initial: HttpHeaders,
	previous: Url,
	old: Url,
	next: Url,
	keep_body: Bool,
) HttpHeaders!:
	subdomain := is_domain_or_subdomain(next.host, previous.host)
	origin := same_origin(next, old)
	var out = headers()
	for name in initial.names():
		if not keep_body and is_entity_header(name): continue
		if is_credential(name) and not subdomain: continue
		if is_origin_credential(name) and not origin: continue
		values := initial.get_all_bytes(name).get_or([])
		for value in values:
			out.append_bytes(name, value)?
	return ok(out)

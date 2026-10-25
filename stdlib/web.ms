from "@std/core.ms" import Closeable
from "@std/http.ms" import Request, Response, Body, HttpError, HttpMethod, Middleware, headers, text_response
from "@std/net.ms" import QueryEntry, parse_query, parse
from "@std/encoding.ms" import base64_decode
from "@std/html.ms" import escape

# One cookie name/value pair; duplicate names remain separate and ordered.
export type CookiePair:
    # Case-sensitive cookie name.
    name: String
    # Unquoted cookie value; no percent decoding is implicit.
    value: String

# Browser cross-site cookie policy.
export type SameSite:
    # Send on same-site requests and safe top-level navigation.
    case Lax
    # Send only on same-site requests.
    case Strict
    # Permit cross-site requests; requires Secure.
    case None

# One Set-Cookie field. Cookie values are ASCII cookie-octets; encode arbitrary data first.
export type Cookie:
    # Case-sensitive name; __Host- and __Secure- prefixes enforce their browser constraints.
    name: String
    # Literal value; no escaping or percent encoding is implicit.
    value: String
    # Absolute cookie path; defaults to / and rejects control characters or semicolons.
    path: String = "/"
    # Domain attribute; none creates a host-only cookie.
    domain: Optional[String] = none
    # Restrict transport to HTTPS.
    secure: Bool = True
    # Prevent JavaScript cookie access.
    http_only: Bool = True
    # Cross-site sending policy.
    same_site: SameSite = SameSite.Lax
    # Lifetime in seconds; zero deletes, none creates a browser-session cookie.
    max_age_seconds: Optional[Int] = none

def token(text: String) -> Bool:
    if text == "": return False

    for value in text.scalar_values():
        if value >= 48 and value <= 57: continue
        if value >= 65 and value <= 90: continue
        if value >= 97 and value <= 122: continue
        if [33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126].contains(
            value
        ): continue

        return False

    return True

def cookie_value(text: String) -> Bool:
    for value in text.scalar_values():
        if value == 33: continue
        if value >= 35 and value <= 43: continue
        if value >= 45 and value <= 58: continue
        if value >= 60 and value <= 91: continue
        if value >= 93 and value <= 126: continue

        return False

    return True

def field_text(
    request: Request,
    name: String,
    max_bytes: Int
) -> Result[Optional[String], HttpError]:
    if max_bytes < 0: return error(HttpError.InvalidInput)

    let found = request.headers.values(name)
    if found.is_none(): return ok(none)

    let values = found.get()
    if values.length() != 1: return error(HttpError.InvalidInput)
    if values[0].length() > max_bytes: return error(HttpError.LimitExceeded)

    let text = values[0].decode_utf8()
    if text.is_none(): return error(HttpError.InvalidInput)

    return ok(some(text.get().clone()))

# Parses Cookie fields in wire order, preserving duplicates. Malformed names/values fail.
# Limits bound total input bytes and cookie count before the returned list grows.
export def cookies(
    request: Request,
    max_bytes: Int = 8192,
    max_cookies: Int = 64
) -> Result[List[CookiePair], HttpError]:
    if max_bytes < 0 or max_cookies < 0: return error(HttpError.InvalidInput)

    var result = List[CookiePair]()
    let found = request.headers.values("Cookie")
    if found.is_none(): return ok(result)

    var size = 0

    for value in found.get():
        if value.length() > max_bytes - size: return error(HttpError.LimitExceeded)

        size += value.length()

    for value in found.get():
        let text = value.decode_utf8()
        if text.is_none(): return error(HttpError.InvalidInput)

        for item in text.get().split(";"):
            if result.length() >= max_cookies: return error(HttpError.LimitExceeded)

            let parts = item.trim().split("=")
            if parts.length() < 2 or not token(parts[0]): return error(
                HttpError.InvalidInput
            )

            var content = parts.slice(1, parts.length()).get().join("=")
            if (
                content.starts_with("\"")
                and content.ends_with("\"")
                and content.byte_length() >= 2
            ):
                content = content.slice(1, content.scalar_length() - 1).get()
            if not cookie_value(content): return error(HttpError.InvalidInput)

            result.append(CookiePair(parts[0].clone(), content))

    return ok(result)

# Appends a separate Set-Cookie field after validating all attributes; never joins cookie fields.
export def set_cookie(
    response: Response,
    cookie: Cookie,
    max_bytes: Int = 4096
) -> Result[Unit, HttpError]:
    if max_bytes < 0: return error(HttpError.InvalidInput)

    var remaining = max_bytes

    for size in [
        cookie.name.byte_length(), cookie.value.byte_length(), cookie.path.byte_length()
    ]:
        if size > remaining: return error(HttpError.LimitExceeded)

        remaining -= size

    if let domain = cookie.domain:
        if domain.byte_length() > remaining: return error(HttpError.LimitExceeded)
    if not token(cookie.name) or not cookie_value(cookie.value): return error(
        HttpError.InvalidInput
    )
    if not cookie.path.starts_with("/"): return error(HttpError.InvalidInput)

    for value in cookie.path.scalar_values():
        if value < 32 or value > 126 or value == 59: return error(
            HttpError.InvalidInput
        )
    if cookie.same_site == SameSite.None and not cookie.secure: return error(
        HttpError.InvalidInput
    )
    if cookie.name.starts_with("__Secure-") and not cookie.secure: return error(
        HttpError.InvalidInput
    )
    if (
        cookie.name.starts_with("__Host-")
        and (not cookie.secure or cookie.path != "/" or cookie.domain.is_some())
    ): return error(HttpError.InvalidInput)

    var value = f"{cookie.name}={cookie.value}; Path={cookie.path}"

    if let domain = cookie.domain:
        if domain == "" or domain.starts_with(".") or domain.ends_with("."): return error(
            HttpError.InvalidInput
        )

        for label in domain.split("."):
            if label == "" or label.starts_with("-") or label.ends_with("-"): return error(
                HttpError.InvalidInput
            )

            for code in label.scalar_values():
                if code >= 48 and code <= 57: continue
                if code >= 65 and code <= 90: continue
                if code >= 97 and code <= 122: continue
                if code == 45: continue

                return error(HttpError.InvalidInput)

        value += f"; Domain={domain}"

    if let age = cookie.max_age_seconds:
        if age < 0: return error(HttpError.InvalidInput)

        value += f"; Max-Age={age}"

    if cookie.secure: value += "; Secure"
    if cookie.http_only: value += "; HttpOnly"

    match cookie.same_site:
        case Lax: value += "; SameSite=Lax"
        case Strict: value += "; SameSite=Strict"
        case None: value += "; SameSite=None"

    if value.byte_length() > max_bytes: return error(HttpError.LimitExceeded)

    return response.headers.append("Set-Cookie", value.to_bytes())

# Extracts one bearer credential without authenticating it; absent or other schemes return none.
# Duplicate Authorization fields and malformed bearer syntax return InvalidInput.
export def bearer_token(
    request: Request,
    max_bytes: Int = 8192
) -> Result[Optional[String], HttpError]:
    let field = try field_text(request, "Authorization", max_bytes)
    if field.is_none(): return ok(none)

    let parts = field.get().split(" ")
    if parts[0].lower() != "bearer": return ok(none)
    if parts.length() != 2 or parts[1] == "" or parts[1].starts_with("="): return error(
        HttpError.InvalidInput
    )

    var padding = False

    for code in parts[1].scalar_values():
        if code == 61:
            padding = True
            continue

        if padding: return error(HttpError.InvalidInput)
        if code >= 48 and code <= 57: continue
        if code >= 65 and code <= 90: continue
        if code >= 97 and code <= 122: continue
        if [45, 46, 95, 126, 43, 47].contains(code): continue

        return error(HttpError.InvalidInput)

    return ok(some(parts[1].clone()))

# Decoded Basic credentials; callers must authenticate and choose an appropriate transport.
export type BasicCredentials:
    # Text before the first colon.
    username: String
    # Remaining text, including any later colons.
    password: String

# Strict Base64/UTF-8 Basic decoding. Absent or other schemes return none; duplicate fields fail.
export def basic_credentials(
    request: Request,
    max_bytes: Int = 8192
) -> Result[Optional[BasicCredentials], HttpError]:
    let field = try field_text(request, "Authorization", max_bytes)
    if field.is_none(): return ok(none)

    let parts = field.get().split(" ")
    if parts[0].lower() != "basic": return ok(none)
    if parts.length() != 2: return error(HttpError.InvalidInput)

    let decoded = base64_decode(parts[1], max_bytes: max_bytes)
    if decoded.is_error(): return error(HttpError.InvalidInput)

    let text = decoded.get().decode_utf8()
    if text.is_none(): return error(HttpError.InvalidInput)

    let pair = text.get().split(":")
    if pair.length() < 2: return error(HttpError.InvalidInput)

    for code in text.get().scalar_values():
        if code < 32 or code == 127: return error(HttpError.InvalidInput)
    return ok(
        some(
            BasicCredentials(
                pair[0].clone(), pair.slice(1, pair.length()).get().join(":")
            )
        )
    )

# Reads a bounded UTF-8 application/x-www-form-urlencoded body with repeated keys preserved.
# Limits bound encoded and decoded bytes and field count; unsupported media/charset is InvalidInput.
export def form(
    request: Request,
    max_bytes: Int = 1048576,
    max_fields: Int = 1024
) -> Result[List[QueryEntry], HttpError]:
    if max_bytes < 0 or max_fields < 0: return error(HttpError.InvalidInput)

    let media = try field_text(request, "Content-Type", 256)
    if media.is_none(): return error(HttpError.InvalidInput)

    let parts = media.get().lower().split(";")
    if parts[0].trim() != "application/x-www-form-urlencoded": return error(
        HttpError.InvalidInput
    )

    for index in parts.slice(1, parts.length()).get():
        if index.trim() != "charset=utf-8": return error(HttpError.InvalidInput)

    let bytes = request.read_body(max_bytes)
    if bytes.is_error(): return error(HttpError.Failed(bytes.err().message()))

    let text = bytes.get().decode_utf8()
    if text.is_none(): return error(HttpError.InvalidInput)

    let entries = parse_query(text.get(), max_fields)
    if entries.is_error(): return error(HttpError.InvalidInput)

    var remaining = max_bytes

    for entry in entries.get():
        let size = entry.key.byte_length() + entry.value.byte_length()
        if size > remaining: return error(HttpError.LimitExceeded)

        remaining -= size

    return ok(entries.get().clone())

# Creates a redirect with a validated HTTP(S) absolute URL or single-slash local path.
# local_only rejects external and scheme-relative locations; use it for untrusted return paths.
export def redirect(
    location: String,
    status: Int = 303,
    local_only: Bool = True
) -> Result[Response, HttpError]:
    if not [301, 302, 303, 307, 308].contains(status): return error(
        HttpError.InvalidInput
    )

    for code in location.scalar_values():
        if code <= 32 or code == 127 or code == 92: return error(HttpError.InvalidInput)

    let local = location.starts_with("/") and not location.starts_with("//")

    if not local:
        if local_only: return error(HttpError.InvalidInput)

        let url = parse(location)
        if url.is_error(): return error(HttpError.InvalidInput)
        if url.get().scheme != "http" and url.get().scheme != "https": return error(
            HttpError.InvalidInput
        )

    let fields = headers()
    try fields.append("Location", location.to_bytes())
    return ok(Response(status, fields, Body.Buffered("".to_bytes())))

# Returns explicitly trusted markup as UTF-8 HTML. Use html_text for untrusted text nodes.
export def html(markup: String, status: Int = 200) -> Response:
    let fields = headers()
    fields.append("Content-Type", "text/html; charset=utf-8".to_bytes()).get()
    fields.append("X-Content-Type-Options", "nosniff".to_bytes()).get()
    return Response(status, fields, Body.Buffered(markup.to_bytes()))

# Escapes text for an HTML text node; not for script, style, URL, or arbitrary attribute contexts.
export def html_text(text: String) -> String:
    return escape(text)

# Explicit cross-origin policy. Origins must be serialized HTTP(S) origins, or a lone * without credentials.
export type Cors:
    # Exact allowed origins; empty denies cross-origin requests.
    origins: List[String] = []
    # Allowed preflight method tokens, compared case-sensitively.
    methods: List[String] = ["GET", "HEAD", "POST"]
    # Allowed request header names, compared case-insensitively.
    request_headers: List[String] = []
    # Response fields accessible to browser scripts.
    expose_headers: List[String] = []
    # Allow credentials only with explicit origins.
    credentials: Bool = False
    # Browser preflight cache lifetime in seconds.
    max_age_seconds: Int = 600

def serialized_origin(origin: String) -> Bool:
    let parsed = parse(origin)
    if parsed.is_error(): return False

    let value = parsed.get()
    if value.scheme != "http" and value.scheme != "https": return False
    if value.query != "" or value.fragment != "": return False

    # A serialized origin has no slash after its scheme separator.
    let parts = origin.split("://")
    return (
        parts.length() == 2
        and not parts[1].contains("/")
        and not parts[1].contains("?")
        and not parts[1].contains("#")
    )

def vary(response: Response, names: List[String]) -> Unit:
    var present = List[String]()
    if let fields = response.headers.text("Vary").get():
        for field in fields:
            for name in field.split(","): present.append(name.trim().lower())

    for name in names:
        if not present.contains("*") and not present.contains(name.lower()):
            response.headers.append("Vary", name.to_bytes()).get()
            present.append(name.lower())

# Validates a policy once and returns ordinary router middleware.
# OPTIONS is preflight only with Origin and Access-Control-Request-Method; denied requests return 403.
export def cors(policy: Cors) -> Result[Middleware, HttpError]:
    if policy.max_age_seconds < 0: return error(HttpError.InvalidInput)
    if (
        policy.origins.contains("*")
        and (policy.credentials or policy.origins.length() != 1)
    ): return error(HttpError.InvalidInput)

    for origin in policy.origins:
        if origin != "*" and not serialized_origin(origin): return error(
            HttpError.InvalidInput
        )
    for name in (
        policy
        .methods
        .concat(policy.request_headers)
        .concat(policy.expose_headers)
    ):
        if not token(name) or name == "*": return error(HttpError.InvalidInput)

    let frozen = policy.clone()
    return ok(Middleware(lambda request, next: cors_dispatch(frozen, request, next)))

def cors_denied(message: String, status: Int) -> Response:
    let response = text_response(message, status)
    vary(
        response,
        [
            "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"
        ]
    )
    return response

type CorsPlan:
    origin: Optional[String] = none
    response: Optional[Response] = none

type CorsHeld[T]:
    value: T

impl Closeable for CorsHeld[T]:
    var def close() -> Unit: ()

extern def msrt_shield_enter() -> Unit

extern def msrt_shield_exit() -> Unit

type CorsPreparation:
    active: Bool = True

impl Closeable for CorsPreparation:
    var def close() -> Unit: msrt_shield_exit()

def cors_dispatch(
    policy: Cors,
    request: Request,
    next: Callable[[Request], Response]
) -> Response:
    with let plan = CorsHeld(cors_plan(policy, request)):
        if plan.value.response.is_some(): return plan.value.response.get().clone()

        with let response = CorsHeld(next(request)):
            return cors_finish(policy, plan.value.origin, response.value)

def cors_plan(policy: Cors, request: Request) -> CorsPlan:
    msrt_shield_enter()

    with let preparation = CorsPreparation():
        let origin_result = field_text(request, "Origin", 2048)
        if origin_result.is_error(): return CorsPlan(
            response: some(cors_denied("Invalid origin", 400))
        )

        let origin = origin_result.get()
        if origin.is_none(): return CorsPlan()
        if not serialized_origin(origin.get()): return CorsPlan(
            response: some(cors_denied("Invalid origin", 400))
        )
        if (
            not policy.origins.contains("*")
            and not policy.origins.contains(origin.get())
        ): return CorsPlan(response: some(cors_denied("Origin not allowed", 403)))

        let requested = field_text(request, "Access-Control-Request-Method", 128)
        if requested.is_error(): return CorsPlan(
            response: some(cors_denied("Invalid preflight", 400))
        )
        if request.method != HttpMethod.Options or requested.get().is_none(): return CorsPlan(
            origin.clone()
        )

        return CorsPlan(
            response: some(
                cors_preflight(
                    policy, request, origin, requested.get().get()
                )
            )
        )

def cors_preflight(
    policy: Cors,
    request: Request,
    origin: Optional[String],
    method: String
) -> Response:
    let response = text_response("", 204)
    if not token(method) or not policy.methods.contains(method): return cors_denied(
        "Method not allowed", 403
    )

    let fields = field_text(request, "Access-Control-Request-Headers", 8192)
    if fields.is_error(): return cors_denied("Invalid preflight", 400)

    var allowed = List[String]()
    for name in policy.request_headers: allowed.append(name.lower())
    if let values = fields.get():
        for name in values.split(","):
            if not token(name.trim()) or not allowed.contains(name.trim().lower()): return cors_denied(
                "Header not allowed", 403
            )
    (
        response.headers.append(
            "Access-Control-Allow-Methods", policy.methods.join(", ").to_bytes()
        ).get()
    )
    if policy.request_headers.length() > 0: (
        response
        .headers
        .append(
            "Access-Control-Allow-Headers", policy.request_headers.join(", ").to_bytes()
        )
        .get()
    )
    (
        response.headers.append(
            "Access-Control-Max-Age", f"{policy.max_age_seconds}".to_bytes()
        ).get()
    )
    vary(response, ["Access-Control-Request-Method", "Access-Control-Request-Headers"])
    return cors_finish(policy, origin, response)

def cors_finish(policy: Cors, origin: Optional[String], response: Response) -> Response:
    msrt_shield_enter()

    with let preparation = CorsPreparation():
        if origin.is_none():
            vary(response, ["Origin"])
            return response.clone()

        vary(response, ["Origin"])
        for name in [
            "Access-Control-Allow-Origin", "Access-Control-Allow-Credentials",
            "Access-Control-Expose-Headers"
        ]: (response.headers.remove(name))
        (
            response.headers.append(
                "Access-Control-Allow-Origin",
                (
                    "*" if policy
                    .origins
                    .contains("*") else origin
                    .get()
                ).to_bytes()
            ).get()
        )
        if policy.credentials: (
            response
            .headers
            .append("Access-Control-Allow-Credentials", "true".to_bytes())
            .get()
        )
        if policy.expose_headers.length() > 0: (
            response
            .headers
            .append(
                "Access-Control-Expose-Headers",
                policy.expose_headers.join(", ").to_bytes()
            )
            .get()
        )
        return response.clone()

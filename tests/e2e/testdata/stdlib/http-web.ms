from "@std/web.ms" import Cookie, SameSite, cookies, set_cookie, Cors, cors, bearer_token, basic_credentials, form, redirect, html, html_text
from "@std/http.ms" import Request, HttpMethod, HttpError, headers, text_response, Router
from "@std/streams.ms" import from_bytes
from "@std/testing.ms" import expect_equal, expect_true

test "cookies preserve duplicates and render separate validated Set-Cookie fields":
    let fields = headers()
    try fields.append("Cookie", "a=one; a=two; token=\"a==\"".to_bytes())

    let parsed = try cookies(Request(headers: fields))
    try expect_equal(parsed.length(), 3)
    try expect_equal(parsed[1].value, "two")
    try expect_equal(parsed[2].value, "a==")

    let response = text_response("ok")
    try set_cookie(response, Cookie("__Host-session", "abc"))
    try set_cookie(response, Cookie("theme", "dark", max_age_seconds: 0))
    try expect_equal(response.headers.values("Set-Cookie").get().length(), 2)
    try expect_true(
        response.headers.text("Set-Cookie").get().get() [0].contains(
            "Secure; HttpOnly; SameSite=Lax"
        )
    )
    try expect_equal(
        set_cookie(
            response, Cookie("__Host-session", "abc", secure: False)
        ).err(),
        HttpError.InvalidInput
    )
    try expect_equal(
        set_cookie(
            response, Cookie("x", "abc", secure: False, same_site: SameSite.None)
        ).err(),
        HttpError.InvalidInput
    )
    try expect_equal(
        set_cookie(response, Cookie("x", "abc\r\nInjected: true")).err(),
        HttpError.InvalidInput
    )
    try expect_equal(
        cookies(Request(headers: fields), max_cookies: 1).err(), HttpError.LimitExceeded
    )

test "credential extraction rejects ambiguity and preserves colons in Basic passwords":
    let fields = headers()
    try fields.append("Authorization", "Basic dXNlcjpwOmFzcw==".to_bytes())

    let decoded = (try basic_credentials(Request(headers: fields))).get()
    try expect_equal(decoded.username, "user")
    try expect_equal(decoded.password, "p:ass")
    fields.remove("Authorization")
    try fields.append("Authorization", "Bearer abc-_.~+/==".to_bytes())
    try expect_equal((try bearer_token(Request(headers: fields))).get(), "abc-_.~+/==")
    fields.remove("Authorization")
    try fields.append("Authorization", "Bearer ===".to_bytes())
    try expect_equal(
        bearer_token(Request(headers: fields)).err(), HttpError.InvalidInput
    )
    try fields.append("Authorization", "Bearer other".to_bytes())
    try expect_equal(
        bearer_token(Request(headers: fields)).err(), HttpError.InvalidInput
    )

test "form decoding preserves repeated values and validates encoding":
    let fields = headers()
    try fields.append(
        "Content-Type", "application/x-www-form-urlencoded; charset=utf-8".to_bytes()
    )

    let entries = try form(
        Request(
            headers: fields, body: from_bytes("a=one&a=two+words&empty=".to_bytes())
        )
    )
    try expect_equal(entries.length(), 3)
    try expect_equal(entries[1].value, "two words")
    try expect_equal(entries[2].value, "")
    try expect_true(
        form(
            Request(headers: fields, body: from_bytes("a=%zz".to_bytes()))
        ).is_error()
    )
    try expect_true(
        form(
            Request(
                headers: fields, body: from_bytes("a=12345".to_bytes())
            ),
            max_bytes: 3
        ).is_error()
    )

test "CORS validates preflights and composes with ordinary OPTIONS and response Vary":
    let policy = Cors(
        origins: ["https://app.example"], methods: ["GET", "POST"],
        request_headers: ["Authorization"], credentials: True
    )
    let middleware = try cors(policy)
    var routes = Router()
    routes.use(middleware.call)

    routes.get(
        "/",
        lambda request:
            let response = text_response("hello")
            response.headers.append("Vary", "Accept-Encoding".to_bytes()).get()
            return response
    )

    let without_origin = routes.handle(Request())
    try expect_equal(without_origin.headers.values("Vary").get().length(), 2)

    let fields = headers()
    try fields.append("Origin", "https://app.example".to_bytes())

    let normal = routes.handle(Request(headers: fields))
    try expect_equal(normal.status, 200)
    try expect_equal(
        normal.headers.text("Access-Control-Allow-Origin").get().get() [0],
        "https://app.example"
    )
    try expect_equal(normal.headers.values("Vary").get().length(), 2)
    try fields.append("Access-Control-Request-Method", "POST".to_bytes())
    try fields.append("Access-Control-Request-Headers", "authorization".to_bytes())

    let preflight = routes.handle(Request(method: HttpMethod.Options, headers: fields))
    try expect_equal(preflight.status, 204)
    try expect_equal(
        preflight.headers.text("Access-Control-Allow-Credentials").get().get() [
            0
        ],
        "true"
    )
    fields.remove("Access-Control-Request-Headers")
    try fields.append("Access-Control-Request-Headers", "X-Not-Allowed".to_bytes())
    try expect_equal(
        routes.handle(
            Request(method: HttpMethod.Options, headers: fields)
        ).status,
        403
    )
    try expect_equal(
        cors(Cors(origins: ["*"], credentials: True)).err(), HttpError.InvalidInput
    )
    try expect_equal(routes.handle(Request(method: HttpMethod.Options)).status, 204)

test "redirects default to local locations and HTML interpolation stays explicit":
    try expect_equal((try redirect("/account?tab=settings")).status, 303)
    for location in [
        "//evil.example", "https://evil.example", "/\\evil.example", "/ok\r\nX:bad"
    ]:
        try expect_true(redirect(location).is_error())
    try expect_equal(
        (try redirect("https://example.com/", local_only: False)).status, 303
    )
    try expect_true(redirect("javascript:alert(1)", local_only: False).is_error())

    let escaped = html_text("<script>&\"")
    try expect_true(not escaped.contains("<script>"))

    let response = html(f"<h1>{escaped}</h1>")
    try expect_equal(
        response.headers.text("Content-Type").get().get() [0],
        "text/html; charset=utf-8"
    )

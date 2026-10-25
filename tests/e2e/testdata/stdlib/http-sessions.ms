from "@std/web_sessions.ms" import SessionKey, Sessions, SessionError
from "@std/web.ms" import Cookie
from "@std/http.ms" import Request, headers, text_response
from "@std/time.ms" import timestamp
from "@std/testing.ms" import expect_equal, expect_true

type User:
    id: Int
    role: String

def old_key() -> SessionKey: return SessionKey(
    "old", "0123456789abcdef0123456789abcdef".to_bytes()
)

def new_key() -> SessionKey: return SessionKey(
    "new", "fedcba9876543210fedcba9876543210".to_bytes()
)

test "sessions verify typed claims rotate keys and reject expired or tampered tokens":
    let now = try timestamp(1700000000, 0)
    let expires = try timestamp(1700000060, 0)
    let original = Sessions[User]([old_key()], "account")
    let rotated = Sessions[User]([new_key(), old_key()], "account")
    let token = try original.issue(User(7, "reader"), expires, now)
    let user = try rotated.verify(token, now)
    try expect_equal(user.id, 7)
    try expect_equal(user.role, "reader")
    try expect_equal(rotated.verify(token, expires).err(), SessionError.Expired)
    try expect_equal(
        Sessions[User]([new_key()], "account").verify(token, now).err(),
        SessionError.InvalidToken
    )
    try expect_equal(
        Sessions[User]([old_key()], "other").verify(token, now).err(),
        SessionError.InvalidToken
    )
    try expect_equal(
        Sessions[User](
            [old_key()], "account", cookie: Cookie("other", "")
        ).verify(token, now).err(),
        SessionError.InvalidToken
    )
    try expect_equal(
        original.verify(
            token.replace_first("1700000060", "1700000999"), now
        ).err(),
        SessionError.InvalidToken
    )
    try expect_equal(
        original.issue(User(1, "a"), now, now).err(), SessionError.InvalidInput
    )

test "sessions reject malformed configuration and oversized tokens":
    let now = try timestamp(1700000000, 0)
    let expires = try timestamp(1700000060, 0)
    for keys in [
        List[SessionKey](), [old_key(), old_key()],
        [SessionKey("has.dot", old_key().secret)],
        [SessionKey("short", "bad".to_bytes())]
    ]:
        try expect_equal(
            Sessions[User](keys, "account").issue(
                User(7, "reader"), expires, now
            ).err(),
            SessionError.InvalidInput
        )

    let small = Sessions[User]([old_key()], "account", max_token_bytes: 20)
    try expect_true(small.issue(User(7, "reader"), expires, now).is_error())
    try expect_equal(
        small.verify("x".repeat(21).get(), now).err(), SessionError.LimitExceeded
    )

test "session cookies reject duplicate names and use the same expiry for Max-Age":
    let now = try timestamp(1700000000, 0)
    let expires = try timestamp(1700000060, 0)
    let sessions = Sessions[User]([old_key()], "account")
    let token = try sessions.issue(User(7, "reader"), expires, now)
    let fields = headers()
    try fields.append("Cookie", f"__Host-session={token}".to_bytes())

    let user = (try sessions.read(Request(headers: fields), now)).get()
    try expect_equal(user.id, 7)
    try fields.append("Cookie", f"__Host-session={token}".to_bytes())
    try expect_equal(
        sessions.read(Request(headers: fields), now).err(), SessionError.InvalidToken
    )

    let response = text_response("ok")
    try sessions.write(response, User(7, "reader"), expires, now)
    try expect_true(
        response.headers.text("Set-Cookie").get().get() [0].contains(
            "Max-Age=60"
        )
    )
    try sessions.clear(response)
    try expect_true(
        response.headers.text("Set-Cookie").get().get() [1].contains(
            "Max-Age=0"
        )
    )

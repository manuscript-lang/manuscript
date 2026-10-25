from "@std/web.ms" import Cookie, cookies, set_cookie
from "@std/http.ms" import Request, Response, HttpError
from "@std/bytes.ms" import Bytes
from "@std/crypto.ms" import HashAlgorithm, constant_time_equal
from "@std/encoding.ms" import base64_encode, base64_decode
from "@std/json.ms" import parse, stringify, JsonLimits, JsonError, JsonValue
from "@std/time.ms" import Timestamp, wall_clock

# Explicit shared signing material. Configure identical keys in each worker/process.
export type SessionKey:
    # Unique rotation identifier, 1..32 characters from A-Z, a-z, 0-9, underscore and hyphen.
    id: String
    # At least 32 secret bytes from a cryptographically secure source; never generated implicitly.
    secret: Bytes

# Session failures distinguish configuration, invalid credentials, expiry, and encoding limits.
export type SessionError:
    # Keys, identifiers, purpose, expiry or limits are invalid.
    case InvalidInput
    # Token syntax, signature, authenticated payload shape, or duplicate cookie names are invalid.
    case InvalidToken
    # An authenticated session has reached its expiry time.
    case Expired
    # A token or cookie exceeds its configured byte bound.
    case LimitExceeded
    # Typed JSON encoding failed.
    case Encoding(
        # Original JSON failure without token contents.
        cause: JsonError
    )
    # Cookie parsing or rendering failed.
    case CookieError(
        # Original HTTP error without session token contents.
        cause: HttpError
    )

impl Error for SessionError:
    # Returns a diagnostic without credentials or token contents.
    def message() -> String:
        match self:
            case InvalidInput: return "Session: invalid configuration or expiry"
            case InvalidToken: return "Session: invalid token"
            case Expired: return "Session: expired"
            case LimitExceeded: return "Session: byte limit exceeded"
            case Encoding(cause): return cause.message()
            case CookieError(cause): return cause.message()

# Signed, readable JSON sessions with key rotation. Provides integrity and expiry, not encryption.
# Revocation and CSRF protection require application policy; share stable keys across members.
export type Sessions[T]:
    # First key signs; all keys verify by ID. Between one and sixteen unique keys are required.
    keys: List[SessionKey]
    # Application-specific domain separation; use a distinct purpose for unrelated applications.
    purpose: String
    # Cookie attributes and name; value and max_age_seconds are replaced when writing.
    cookie: Cookie = Cookie("__Host-session", "")
    # Maximum encoded token bytes. Full Set-Cookie output is independently capped at 4096 bytes.
    max_token_bytes: Int = 3072

def key_id(value: String) -> Bool:
    if value == "" or value.byte_length() > 32: return False

    for code in value.scalar_values():
        if code >= 48 and code <= 57: continue
        if code >= 65 and code <= 90: continue
        if code >= 97 and code <= 122: continue
        if code == 45 or code == 95: continue

        return False

    return True

impl Sessions[T]:
    # Checks explicit key configuration without revealing secrets.
    def validate() -> Result[Unit, SessionError]:
        if self.keys.length() < 1 or self.keys.length() > 16: return error(
            SessionError.InvalidInput
        )
        if (
            self.purpose == ""
            or self.purpose.byte_length() > 128
            or self.max_token_bytes <= 0
        ): return error(SessionError.InvalidInput)
        if self.cookie.name == "" or self.cookie.name.byte_length() > 128: return error(
            SessionError.InvalidInput
        )

        var ids = List[String]()

        for key in self.keys:
            if not key_id(key.id) or key.secret.length() < 32 or ids.contains(key.id): return error(
                SessionError.InvalidInput
            )

            ids.append(key.id.clone())

        return ok(())

    # Internal length-delimited purpose and cookie-name binding for HMAC input.
    def authenticated(text: String) -> Bytes:
        return f"manuscript-session-v1\n{self.purpose.byte_length()}:{self.purpose}{self.cookie.name.byte_length()}:{self.cookie.name}\n{text}".to_bytes()

    # Signs typed JSON using the first configured key. Expiry must be after now at whole-second precision.
    def issue(
        value: T,
        expires: Timestamp,
        now: Timestamp = wall_clock().now()
    ) -> Result[String, SessionError]:
        try self.validate()
        if expires.unix_seconds() <= now.unix_seconds(): return error(
            SessionError.InvalidInput
        )

        let encoded = stringify(value, max_bytes: self.max_token_bytes, strict: True)
        if encoded.is_error(): return error(
            SessionError.Encoding(encoded.err().clone())
        )

        let checked = parse[JsonValue](
            encoded.get(),
            JsonLimits(
                max_bytes: self.max_token_bytes, max_depth: 64, max_values: 4096
            )
        )
        if checked.is_error(): return error(
            SessionError.Encoding(checked.err().clone())
        )

        let payload = base64_encode(encoded.get().to_bytes(), url_safe: True)
        let text = f"v1.{self.keys[0].id}.{expires.unix_seconds()}.{payload}"

        # A SHA-256 MAC occupies 44 Base64 bytes plus the delimiter.
        if self.max_token_bytes < 45 or text.byte_length() > self.max_token_bytes - 45: return error(
            SessionError.LimitExceeded
        )

        let signature = (
            HashAlgorithm
            .Sha256
            .hmac(self.keys[0].secret, self.authenticated(text))
        )
        if signature.is_error(): return error(SessionError.InvalidInput)

        return ok(text + "." + base64_encode(signature.get(), url_safe: True))

    # Verifies MAC before decoding expiry or JSON claims. Unknown/retired key IDs are invalid tokens.
    def verify(
        token: String,
        now: Timestamp = wall_clock().now()
    ) -> Result[T, SessionError]:
        try self.validate()
        if token.byte_length() > self.max_token_bytes: return error(
            SessionError.LimitExceeded
        )

        let parts = token.split(".")
        if parts.length() != 5 or parts[0] != "v1" or not key_id(parts[1]): return error(
            SessionError.InvalidToken
        )

        var selected: Optional[Bytes] = none
        for key in self.keys:
            if key.id == parts[1]: selected = some(key.secret.clone())
        if selected.is_none(): return error(SessionError.InvalidToken)

        let supplied = base64_decode(parts[4], url_safe: True, max_bytes: 32)
        if supplied.is_error(): return error(SessionError.InvalidToken)
        if supplied.get().length() != 32: return error(SessionError.InvalidToken)

        let text = parts.slice(0, 4).get().join(".")
        let expected = (
            HashAlgorithm
            .Sha256
            .hmac(selected.get(), self.authenticated(text))
        )
        if expected.is_error(): return error(SessionError.InvalidInput)
        if not constant_time_equal(supplied.get(), expected.get()): return error(
            SessionError.InvalidToken
        )

        let expiry = parse[Int](
            parts[2], JsonLimits(max_bytes: 20, max_depth: 1, max_values: 1)
        )
        if expiry.is_error(): return error(SessionError.InvalidToken)
        if expiry.get() <= now.unix_seconds(): return error(SessionError.Expired)

        let bytes = base64_decode(
            parts[3], url_safe: True, max_bytes: self.max_token_bytes
        )
        if bytes.is_error(): return error(SessionError.InvalidToken)

        let decoded = bytes.get().decode_utf8()
        if decoded.is_none(): return error(SessionError.InvalidToken)

        let value = parse[T](
            decoded.get(),
            JsonLimits(
                max_bytes: self.max_token_bytes, max_depth: 64, max_values: 4096
            ),
            ignore_unknown_fields: False
        )

        match value:
            case ok(value): return ok(value)
            case error(cause): return error(SessionError.InvalidToken)

    # Reads one named cookie; duplicate session cookie names are rejected rather than choosing a winner.
    def read(
        request: Request,
        now: Timestamp = wall_clock().now()
    ) -> Result[Optional[T], SessionError]:
        try self.validate()

        let parsed = cookies(request)
        if parsed.is_error(): return error(
            SessionError.CookieError(parsed.err().clone())
        )

        var token: Optional[String] = none

        for cookie in parsed.get():
            if cookie.name != self.cookie.name: continue
            if token.is_some(): return error(SessionError.InvalidToken)

            token = some(cookie.value.clone())

        if token.is_none(): return ok(none)

        let verified = try self.verify(token.get(), now)
        return ok(some(verified))

    # Issues and appends one cookie. Signed expiry and browser Max-Age use the same supplied wall clock.
    def write(
        response: Response,
        value: T,
        expires: Timestamp,
        now: Timestamp = wall_clock().now()
    ) -> Result[Unit, SessionError]:
        let token = try self.issue(value, expires, now)
        let age = expires.difference(now)
        if age.is_error(): return error(SessionError.InvalidInput)

        var cookie = self.cookie.clone()
        cookie.value = token
        cookie.max_age_seconds = some(expires.unix_seconds() - now.unix_seconds())

        let result = set_cookie(response, cookie)
        if result.is_error(): return error(
            SessionError.CookieError(result.err().clone())
        )

        return ok(())

    # Deletes the browser cookie using the same path/domain/security attributes.
    def clear(response: Response) -> Result[Unit, SessionError]:
        var cookie = self.cookie.clone()
        cookie.value = ""
        cookie.max_age_seconds = some(0)

        let result = set_cookie(response, cookie)
        if result.is_error(): return error(
            SessionError.CookieError(result.err().clone())
        )

        return ok(())

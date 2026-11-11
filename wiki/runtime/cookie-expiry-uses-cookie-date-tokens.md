[Wiki](../index.md) › [Runtime](index.md)

# Cookie expiry uses cookie-date tokens

Verified: parsing `Expires` as a rigid HTTP date silently turns valid legacy expiry dates into session cookies. A server's expired replacement then stays in the jar and is sent again (#3352).

Apply when: changing the HTTP client's cookie parsing or jar.
Evidence: [RFC 6265 section 5.1.1](https://www.rfc-editor.org/rfc/rfc6265#section-5.1.1) defines cookie-date tokens, two-digit years and calendar validation; [cookies.rs](../../crates/ms-std-net/src/http/cookies.rs) owns this parser. Invalid Expires attributes are ignored without clearing an earlier valid attribute.
Verify: [http-headers.ms](../../tests/conformance/fixtures/e2e/stdlib/http-headers.ms) checks both RFC850 and asctime deletion over a real client/server exchange; the Rust jar tests cover year boundaries, invalid dates, delimiters and Max-Age precedence, and client tests exercise HTTP/1 and HTTP/2.

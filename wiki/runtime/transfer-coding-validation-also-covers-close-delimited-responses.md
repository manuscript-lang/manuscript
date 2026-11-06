[Wiki](../index.md) › [Runtime](index.md)

# Transfer coding validation also covers close-delimited responses

Verified: checking unsupported response transfer codings only inside the `chunked` branch lets `Transfer-Encoding: gzip` reach the caller still encoded when the connection closes. Reject unsupported codings before choosing framing, and keep transfer coding separate from supported `Content-Encoding` decompression.

Apply when: changing HTTP/1 response framing or client decompression.
Evidence: [`response_framing_rules`](../../crates/ms-std-net/src/http/h1.rs) covers unsupported codings with and without chunked, plus retained identity framing.
Verify: `cargo test -p ms-std-net http::h1::tests::response_framing_rules` rejects `gzip` alone as well as `gzip, chunked`.

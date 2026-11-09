[Wiki](../index.md) › [Runtime](index.md)

# HTTP Content-Type inference does not require a known length

Verified: HTTP/2 streaming responses have no Content-Length while their first
body chunk is already available. Nesting Content-Type inference under the
optional length omitted the type for these responses, unlike HTTP/1. Infer from
the first bytes independently of framing, while retaining an explicit type.

Apply when: changing HTTP response serialization or streaming writes.
Evidence: [`streaming_response_content_types`](../../crates/ms-std-net/src/http/server/h2serve/tests.rs).
Verify: streamed text and HTML receive their inferred types, explicit types stay
unchanged, and empty/bodyless responses do not acquire a type.

[Wiki](../index.md) › [Runtime](index.md)

# HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.


Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: [called source checks](../../tests/e2e/testdata/stdlib/http-headers.ms), [header contracts](../../stdlib/net/http.ms).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered raw-byte acceptance, streaming/client UTF-8 rejection, transport framing validation and domain errors distinct.

Repeated `Content-Encoding` fields are one ordered coding list. The client only
transparently decodes a single gzip coding; checking the first field alone and
then removing every encoding field left stacked bodies partly compressed without
their metadata. The HTTP/1 and HTTP/2 `stacked_content_encodings_keep_the_body_and_metadata`
tests compare split fields with their comma-combined form and retain the original
encoded bytes and encoding/length fields for both.

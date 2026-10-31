[Wiki](../index.md) › [Runtime](index.md)

# HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.

Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: [called source checks](../../tests/e2e/testdata/stdlib/http-headers.ms), [header contracts](../../stdlib/http.ms).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered raw-byte acceptance, streaming/client UTF-8 rejection, transport framing validation and domain errors distinct. Do not impose a blanket copy-on-read or membership-copy guarantee; explicit text extraction and copy are distinct operations.

---
Topics: [Networking and HTTP](../topics/networking-and-http.md)

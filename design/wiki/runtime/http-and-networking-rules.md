[Wiki](../index.md) › [runtime](index.md)

# HTTP and networking rules

Content-type inference, field folding, redirects, transfer coding, rejected uploads, interruption and shutdown. Each section is one lesson.

## HTTP Content-Type inference does not require a known length

Verified: HTTP/2 streaming responses have no Content-Length while their first
body chunk is already available. Nesting Content-Type inference under the
optional length omitted the type for these responses, unlike HTTP/1. Infer from
the first bytes independently of framing, while retaining an explicit type.

Apply when: changing HTTP response serialization or streaming writes.
Evidence: `streaming_response_content_types`.
Verify: streamed text and HTML receive their inferred types, explicit types stay
unchanged, and empty/bodyless responses do not acquire a type.

## HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.


Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: [called source checks](../../../tests/conformance/fixtures/e2e/stdlib/http-headers.ms), [header contracts](../../../src/stdlib/net/http.ms).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered raw-byte acceptance, streaming/client UTF-8 rejection, transport framing validation and domain errors distinct.

Repeated `Content-Encoding` fields are one ordered coding list. The client only
transparently decodes a single gzip coding; checking the first field alone and
then removing every encoding field left stacked bodies partly compressed without
their metadata. The HTTP/1 and HTTP/2 `stacked_content_encodings_keep_the_body_and_metadata`
tests compare split fields with their comma-combined form and retain the original
encoded bytes and encoding/length fields for both.

## Redirect header removal persists through the entire chain

Verified: rebuilding each redirect from the original request restores credentials after a
cross-origin hop stripped them, and restores entity headers when a 302 drops a body before
a 307 preserves the now-empty body. Filter the previous hop's headers instead. Recompute
automatic Referer on every hop so carrying headers forward cannot leak a prior origin's URL.


Apply when: changing redirect policy or outgoing request header propagation.
Evidence: loopback redirect regressions, [called fetch chain regression](../../../tests/conformance/fixtures/e2e/stdlib/fetch.ms).
Verify: a cross-origin redirect followed by a same-origin redirect sends no original credentials; a 302 then 307 sends neither a body nor its original entity headers; automatic Referer stays local.

## Transfer coding validation also covers close-delimited responses

Verified: checking unsupported response transfer codings only inside the `chunked` branch lets `Transfer-Encoding: gzip` reach the caller still encoded when the connection closes. Reject unsupported codings before choosing framing, and keep transfer coding separate from supported `Content-Encoding` decompression.

Apply when: changing HTTP/1 response framing or client decompression.
Evidence: `response_framing_rules` covers unsupported codings with and without chunked, plus retained identity framing.
Verify: the HTTP/1 response framing tests (`src/runtime/std/http_h1*.c`) reject `gzip` alone as well as `gzip, chunked`.

## Rejected uploads need a bounded half-close before socket retirement

Verified: closing both TCP halves immediately after writing an HTTP/1 rejection can reset a
connection whose peer is still uploading, hiding the response on Windows. Flush the response,
half-close output, and discard input without buffering until peer FIN or a fixed drain deadline.
Check the deadline during read retries as well as the reactor's timeout sweep.


Apply when: changing HTTP rejection responses or connection retirement.
Evidence: rejection drain and socket regressions, [source header-cap regression](../../../tests/conformance/fixtures/e2e/stdlib/http-limits.ms).
Verify: a 2 MB header upload receives the complete 431 response without a reset; a peer that keeps its write half open cannot retain the rejected connection indefinitely.

## Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.


Restriction checks must intersect listening permission as well as host and CIDR filters across every ancestor. Checking only the immediate `Policy.listen` lets a child restore a capability denied by its parent. The regression `child_cannot_restore_parent_listening_permission` covers TCP/UDP denial, deeper descendants, resolver-derived children, and allowed/address-filtered controls; run it before treating this correction as validated.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [architecture](../../../documentation/contributing/architecture.md), [networking project](../../../tests/conformance/fixtures/e2e/projects/networking), [network fixture](../../../tests/conformance/fixtures/e2e/stdlib/net.ms).
Verify: run relevant cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

## STARTTLS moves the descriptor, it does not wrap the connection

Verified: `start_tls` and `accept_tls` (`@std/net/net.ms`) take the socket out of an idle plain `Connection` (`Io::take_plain`), mark that connection closed without shutting the socket, and handshake on a new `Connection`. The `Connection` record keeps a non-stream `native` handle for this, so closing the socket when the last stream end closes counts `ends` in the runtime handle, not a reference count. Busy, closed or already-TLS connections return EINVAL/EBADF and stay usable; a failed handshake consumes the socket.

Apply when: adding a stream wrapper or changing connection close rules.
Evidence: `start_tls upgrades a plain connection in place on both sides` in [tls.ms](../../../tests/conformance/fixtures/e2e/stdlib/tls.ms).

## Timing fixtures

`http-request-deadline` failed on Windows runners with an empty answer (a clean close, no read error) in its first case only (#4492). It does not reproduce on Linux: the same fixture passes 40 of 40 on one pinned core under 24 busy loops, and even a 2 ms server timeout passes, so lazy start-up on Linux costs under 2 ms. The Windows cause is unproven; the fixture's failure output now carries connect, send and end times so the next failure shows where the 200 ms went. Do not paper over it with a warm-up request or a longer timeout: if a real server drops a first connection with no answer, that is a product bug.

A heap check over cancelled calls compares rounds and fails only when every round grows (`http-fault-leak`, one Windows run grew 8976 bytes with no leak).

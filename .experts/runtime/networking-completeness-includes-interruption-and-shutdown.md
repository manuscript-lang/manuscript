[Wiki](../index.md) › [Runtime](index.md)

# Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [architecture](../../documentation/contributing/architecture.md), [networking project](../../tests/e2e/testdata/projects/networking), [network fixture](../../tests/e2e/testdata/stdlib/net.ms).
Verify: run relevant cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

---
Topics: [Networking and HTTP](../topics/networking-and-http.md)

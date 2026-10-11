+++
title = "HTTP request hosts"
weight = 45
+++

# HTTP request hosts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

An HTTP host establishes a fixed execution context for each request, with admission limits, body limits, deadline policy, disconnect cancellation, backpressure, and fault isolation.

Request handlers use `parallel` or `parallel_map` for joined work and `with` for request resources. Client disconnection cancels the request and its nested groups; those groups join and registered cleanup runs before request execution ends.

Streaming responses remain within their request lifetime until streaming finishes. WebSocket/session hosts establish explicit session lifetimes and participate in shutdown; they are not untracked background goroutines.

Application background services are constructed under the application context and passed to handlers. Accepted work uses that service's context, not the submitting request's deadline or disconnect signal. Jobs capture request data and application services and acquire their own resources. Admission can race with request cancellation; idempotent submissions are an application concern.

Server shutdown stops request admission, allows a configured grace period, cancels and joins remaining request/session work, closes background admission and drains/cancels/joins those services, then releases application resources. A finite grace period does not guarantee uncooperative work exits; host escalation is separate.

The API still needs route/session registration, request and response types, streaming operations, configuration limits, and observable disconnect/shutdown outcomes. See [background services](../tasks/background.md), [cancellation](../../concurrency/cancellation.md#propagation-and-checkpoints), and [conformance programs](../../compiler/conformance/programs.md).

# Fewer instructions per HTTP request

## Summary

- Problem: a keep-alive request to a trivial handler costs 19.3k instructions in Manuscript against about 2.5k in a bare C epoll server, so a Manuscript server burns about 5 times the CPU per request at low load (user time 1.2 s against 0.2 s per 40,000 requests in `bench/perf/http-tail`).
- Change, stage 1 (this PR): the content-type check reads 8 bytes per step, and a request task is a detached task instead of a promise. Stage 2 and 3 are listed below and are not in this PR.
- Decision requested: none; no API or behavior change.

## Measured breakdown (callgrind, one thread, 54k requests, trivial handler)

| Phase | Instructions per request |
| --- | --- |
| Parse head | 2.1k |
| Header table build and drop | 2.8k |
| Spawn and end the request task (promise, events, context swaps) | 3.6k |
| Ms handler side (path, query, method strings, headers handle, cleanups) | 2.5k |
| Response (validation, head, date, content-type check, queue) | 4.0k |
| Exchange drop and finish | 1.5k |
| Poller and glue | 1.2k |

## Stage 1 (this PR): 19.3k to 15.9k

- Content-type check: a body that sets no type is scanned for control bytes by 8-byte words with the carry trick, and only a word with a byte below 0x20 looks at its bytes. About 840 per request for a short body, up to 2.5k for the 512 bytes a JSON body gives it.
- Request tasks: the server started each request as a promise (promise slot, closure object, started and ended events, creator lend, a join at drop) only to get a handle for cancelling and a join at close. It already tracks its handler tasks by id, wraps the handler in a fault guard, and counts running handlers for draining. Detached tasks give the same: close cancels the ids and waits until the running count is zero. About 2.5k per request. A fault outside the guarded handler call ends the process (exit 134) instead of one request; the Rust code between the reactor and the guard has no fault path of its own.
- Unchanged: the reactor still yields after starting handlers, so connection stealing (which relies on the reactor turning between events) behaves as before.

## Next stages, not in this PR

- Lazy header table: keep the head bytes and a flat index of name and value offsets, build the table when a program iterates or keeps it. About 2.5k, and only if `HttpRequest.headers` stays exactly as users see it.
- Cheaper promise spawn and end in `ms-rt` for every program: per-thread flat slot arrays and no event objects on the same thread.

## Alternatives considered

- Keep promises and shave them: the promise table and events serve cross-thread waits; same-thread request tasks need none of it, so removing the use is simpler than special cases inside the promise code.
- Run the handler on the reactor's stack until its first wait: a task cannot move stacks once it waits, so a handler that waits would need its own stack from the start. The cost is in the lifecycle around the stack, not the stack.
- Do nothing: user time per request stays about 5 times C's.

## Testing

`cargo test -p ms-std-net` (includes `a_control_byte_is_found_at_every_offset_of_a_long_buffer`), the conformance corpus, and the instruction counts in the bench README.

- Allocator under a limited address space: the heap retries smaller reservations when the 256 GiB map fails and keeps a quarter of the first size that fits (the largest one starved thread and task stacks under `ulimit -v`; `address_limit` runs a threaded, many-task program at 5 GiB), so valgrind and `ulimit -v` run the real allocator. The sizes are runtime values kept in one `Hot` object next to the base and table, so a lookup costs one address load (statics in the runtime archive go through the GOT): 12671 per request against 12685 with compile-time sizes (-14, same smaller reservation).
- Guard: `bench/perf/guards/http-request` counts the server side of 10000 requests (client is a child process, not followed by valgrind) in the nightly `make perf-counts`, held to 1% (about 151.3M, 15.1k per request).

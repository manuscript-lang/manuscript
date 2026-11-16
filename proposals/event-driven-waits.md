# Replace periodic looks with events

## Summary

- Problem: the HTTP server moves connections off a held-up thread by a watcher that wakes every 100 µs to 2 ms to look, and every 10 ms to rebalance. The owner dislikes timed looks: they burn CPU when nothing happens (about 6% of a core under load), miss what happens between looks, and make the runtime hard to reason about.
- Change: nothing looks on a clock. A thread that has a request ready on a connection it cannot serve is announced by the event itself (the kernel's readiness, or the thread's own batch of ready connections), and one deadline per event decides whether the owner served it in time. Balance runs when a connection count changes.
- Decision requested: none; no API, language, or default change. Same PR as the implementation.

## Result of the first implementation (measured 2026-11-16, 4 vCPU VM, alternated runs against `main` at 9f09fd55)

Not mergeable as built; recorded so the next attempt starts here.

| Scenario | `main` | Event-driven rescuer |
| --- | --- | --- |
| Fixture `http-long-handler-does-not-hold-others`, 30 runs | 30 of 30 | 30 of 30 |
| Slow mix, 2000 req/s: p50 / p90 / p99 | 0.63 / 1.23 / 2.7 to 3.3 ms | 0.69 / 1.33 / 3.3 to 4.0 ms |
| Slow mix CPU for the run | 9.6 s | 8.6 s |
| Fast mix, 4000 req/s CPU (40k requests) | 2.8 s | 3.4 to 3.5 s |
| Closed loop, 64 conns | 124k to 127k req/s | 90k to 99k req/s |

- The kernel-readiness source wakes the rescuer thread once per request. On this VM a cross-CPU wake costs about 14 µs of CPU per request, which is 20% of closed-loop throughput and 20% of fast-mix CPU. Turning the nested registration off removed the cost and the help.
- A "turn counter unchanged" test for held up is wrong: the event that reports a request also wakes its owner, which turns before the deadline. "Has not rested since the event" is right (`ms_rt::sched::rests`).
- Re-arming the deadline while a thread stays held up was needed for slow-mix p50 and p90 (0.66 against 0.72 ms), so some looking during a stall is unavoidable without a source that reports each arrival.
- Next attempt: the wake must not be per request. Candidates: register the owners' pollers only while some thread rests and the owner is known busy; or a per-thread `ran_since` stamp that the owner writes at no syscall cost, read by the rescuer, which sleeps on one deadline armed when a thread starts a task that has not ended (needs a no-syscall way to arm it).

## Inventory (2026-11-16, `main` at 9f09fd55)

| Kind | Where | Value | Verdict |
| --- | --- | --- | --- |
| Periodic look | `ms-rt/src/watch.rs` | 100 µs while a hook asks, 2 ms otherwise, sleeps after 100 quiet looks | Remove |
| Periodic look | `http/server/steal.rs` `BALANCE_EVERY` | 10 ms | Remove: balance on count change |
| Periodic look | `http/server.rs` H2 sweep | 50 ms while any HTTP/2 connection lives | Follow-up PR (HTTP/2 stealing): per-stream deadlines |
| Periodic look | `sys/windows.rs` `PARK_NS` | reactor parks at most 50 ms | Follow-up: needs Windows CI to prove no lost wake-up |
| Spin before sleep | `task/reactor.rs` `SPIN_NS` | 20 µs, with credit | Keep: bounded, adaptive, measured; not a wait for a condition |
| One-shot deadline from an event | `sched.rs` `BEAT_NS`, `OWN_HOLD_NS`, steal pause | 20 µs, 1 ms, 50 µs to 2 ms | Keep: a start waits out its age once, then the thread wakes at that instant; no polling |
| One-shot deadline from an event | `poller.rs` short timers, `start.rs` cleanup grace | | Keep |
| Test polls | `watch.rs`, `steal.rs`, `sched.rs` `warm`, `pool.rs` tests, server tests | 1 to 10 ms loops | Replace the ones in code this change touches with condition waits |

Rule used: a wait is acceptable when it is one deadline armed by an event and nothing runs between the event and the deadline. It is not acceptable when something wakes on a period to see whether anything changed.

## Design

Keep what works: a waiting plain HTTP/1 connection is a socket and a deadline in a shared list (`steal::Member`), and a resting thread of the same `serve` call takes the ones with a request waiting. Replace how the need is found.

- Rescuer: one thread, `ms-rescue`, blocked in a `mio::Poll` with no timeout while nothing is pending. It replaces `ms_rt::watch` (deleted, with `Look`, the epoch, and the wake-up stamp).
- Event 1, the kernel: each reactor's poller lends its readiness to the rescuer once. On Unix the poller's own epoll or kqueue descriptor is registered in the rescuer's poll (an epoll descriptor is readable while it holds undelivered events). On Windows the helper thread that already blocks in the poller's `mio::Poll` also wakes the rescuer through a `mio::Waker`. Cost: one registration per thread, not per connection.
- Event 2, the owner: when a reactor has read a batch of ready connections and is about to run a handler while another thread rests, it tells the rescuer. The kernel has nothing more to report for connections already in its batch, so this is the only way to see them.
- Deadline: on an event for owner O the rescuer records O's turn counter (`Beat::turn` counts instead of storing an epoch) and arms one deadline, `HELP_AFTER`, 100 µs, which is the longest a ready request may wait for its owner before it is moved. At the deadline, if O's counter is unchanged, O did not turn: a resting thread of the group is ordered to take the listed connections with a request waiting (`Member::take`, unchanged). If O turned, nothing is done. The poll timeout is the earliest deadline, or none.
- No helper resting: the rescuer keeps the entry and arms a rest hook in `sched::set_idle(true)`, which wakes it when a thread rests. Nothing polls for a helper.
- Balance: `Member::count` compares the group's connection counts when one changes and orders the fewest to take half the difference, as the periodic pass did; one pending order per member.
- Idle server: no pending entry means no timeout, so the rescuer and every reactor sleep until a real event.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt` `watch.rs`, `sched.rs`, `lib.rs` | delete the watcher; rest hook | unit test for the hook |
| `ms-std-net` `http/server/steal.rs` | rescuer, events, deadline, count-driven balance | existing three tests rewritten without sleeps; a test that a held-up owner is rescued and a turning owner is not |
| `ms-std-net` `sys/unix.rs`, `sys/windows.rs` | `Poller::lend_readiness` | steal tests; Windows and macOS CI dispatched on the branch |
| `ms-std-net` `http/server.rs` | batch announcement, count-driven balance | fixture `http-long-handler-does-not-hold-others` |

## Acceptance

- Fixture `http-long-handler-does-not-hold-others` passes on every run of 20.
- `bench/perf/http-tail` slow mix: p99 no worse than `main`; fast mix: p50, p99, CPU for 88,000 requests and closed-loop throughput within the machine's noise of `main` (alternated runs, medians).
- No `std::thread::sleep` or timed loop remains in the code this change touches outside tests that wait on a condition.

## Alternatives

- Do nothing: the 100 µs looks cost CPU under load and 2 ms looks bound the help latency; the owner asked for no tuned waits.
- Owner announces every handler start: one wake-up per request, which the fast path cannot afford.
- Resting threads register every connection of busy threads: a registration and a wake-up per request per thread; kernel exclusive wake-ups exist only on Linux.
- No deadline, move at once whenever the owner is busy: moves connections a short handler would have served in microseconds (measured in the earlier design as lost throughput).

## Follow-up

TLS and HTTP/2 stealing (state moves with the connection, and the 50 ms HTTP/2 sweep becomes per-stream deadlines) in a stacked PR.

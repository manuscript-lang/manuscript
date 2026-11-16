# Replace periodic looks with kernel timers

## Summary

- Problem: the HTTP server moves connections off a held-up thread by a watcher that wakes every 100 µs to 2 ms to look, and every 10 ms to rebalance. The owner dislikes timed looks: they burn CPU when nothing happens (about 6% of a core under load), miss what happens between looks, and make the runtime hard to reason about.
- Change: no thread looks on a clock and no helper thread exists. Each scheduler thread owns a kernel timer that its peers' pollers wait on. A thread arms it when it leaves rest and disarms it when it rests. It fires only for a thread that stayed out of rest for `HELP_AFTER_NS` (250 µs), and then a resting peer takes the connections with a request waiting. Balance runs when a connection count changes. Same mechanism covers plain, TLS and HTTP/2 connections.
- Decision requested: none; no API, language, or default change. One documented number, a deadline with a meaning.

## Design

- Timer per thread (Linux `timerfd`, macOS `kqueue` timer in its own kqueue, Windows thread-pool timer waking the helper's `mio` poll), registered in each peer's poller under a token. A peer's poller reports it as one more event: `Poller::fired`.
- `sched::set_idle` calls two hooks, installed once a `serve` group has two members: leaving rest arms the timer for one resting peer (two system calls, nobody woken); resting disarms it.
- When it fires, the woken peer checks the owner's rest counter (`sched::rests`) and turn counter. Rested since arming: stale. Reactor turned: busy but healthy, re-arm. Neither: held up, take the ready connections (`Member::take`, unchanged) and re-arm so later arrivals in the same stall are found within the same bound.
- With no peer resting nothing is armed; a resting thread arms the timers of such threads for itself as it begins to rest. With every thread at rest nothing is armed and nothing wakes.
- `ms_rt::watch` is deleted. Windows and the 50 ms HTTP/2 sweep are unchanged (see the inventory).

## Measurements (2026-11-16, 4 vCPU VM, alternated runs; base is `main` at 9f09fd55, no TLS/H2 stealing)

| Scenario | Base | Timer design, T = 250 µs |
| --- | --- | --- |
| Fixture `http-long-handler-does-not-hold-others` | 30 of 30 | 20 of 20 |
| Slow mix 2000 req/s: p50 / p99, CPU | 0.64 ms / 3.3 to 3.5 ms, 9.9 s | 0.66 ms / 2.8 to 2.9 ms, 9.0 s |
| Fast mix 4000 req/s, CPU (40k requests) | 2.9 to 3.0 s | 3.1 to 3.4 s (+8 to 13%) |
| Fast mix p50 / p99 | 0.67 ms / 2.1 to 2.6 ms | 0.66 ms / 2.1 ms |
| Saturated closed loop, 64 conns | 79k to 89k req/s | 86k to 96k req/s (equal within noise) |

Dead ends measured on the way:

- A, one shared one-shot poller that every thread waits on: 0 to 20% throughput loss (microbenchmark of epoll, owned vs shared).
- A2, `EPOLLEXCLUSIVE` on a nested epoll descriptor: `EINVAL`.
- B, kernel readiness lent to one rescuer thread (the first implementation): one wake per request, about 14 µs of CPU each, 20% of closed-loop throughput.
- T: CPU of the fast mix grows as 1/T (timers that fire on a thread that is only busy). 100 µs cost +15%, 1 ms lost the slow-mix tail; 250 µs is the compromise.
- A "turn counter unchanged" test alone is wrong: the event that reports a request also wakes its owner. "Has not rested since arming" is the test.

Known cost: the macOS timer filter has a 1 ms floor in this code (`Timer::arm`), so a held-up thread there is found after 1 ms; Windows and macOS are verified by CI only.

## Inventory (2026-11-16, `main` at 9f09fd55)

| Kind | Where | Value | Verdict |
| --- | --- | --- | --- |
| Periodic look | `ms-rt/src/watch.rs` | 100 µs while a hook asks, 2 ms otherwise, sleeps after 100 quiet looks | Removed (kernel timers) |
| Periodic look | `http/server/steal.rs` `BALANCE_EVERY` | 10 ms | Remove: balance on count change |
| Periodic look | `http/server.rs` H2 sweep | 50 ms while any HTTP/2 connection lives | Follow-up PR (HTTP/2 stealing): per-stream deadlines |
| Periodic look | `sys/windows.rs` `PARK_NS` | reactor parks at most 50 ms | Follow-up: needs Windows CI to prove no lost wake-up |
| Spin before sleep | `task/reactor.rs` `SPIN_NS` | 20 µs, with credit | Keep: bounded, adaptive, measured; not a wait for a condition |
| One-shot deadline from an event | `sched.rs` `BEAT_NS`, `OWN_HOLD_NS`, steal pause | 20 µs, 1 ms, 50 µs to 2 ms | Keep: a start waits out its age once, then the thread wakes at that instant; no polling |
| One-shot deadline from an event | `poller.rs` short timers, `start.rs` cleanup grace | | Keep |
| Test polls | `watch.rs`, `steal.rs`, `sched.rs` `warm`, `pool.rs` tests, server tests | 1 to 10 ms loops | Replace the ones in code this change touches with condition waits |

Rule used: a wait is acceptable when it is one deadline armed by an event and nothing runs between the event and the deadline. It is not acceptable when something wakes on a period to see whether anything changed.

## Acceptance

- Fixture `http-long-handler-does-not-hold-others` passes every run of 20.
- Tests: an armed timer is reported by the poller it was made for; a disarmed one reports nothing; a fire on a held-up thread sends the hearer, on a turning or rested one nobody; connection parked state goes to the taker or back.
- Slow-mix p99 no worse than base; fast-mix and closed-loop within the cost above.
- No `std::thread::sleep` or timed loop in the touched code outside tests that wait on a condition.

## Alternatives

- Do nothing: the 100 µs looks cost CPU and 2 ms looks bound the help latency; the owner asked for no tuned waits.
- Owner announces every handler start: one wake-up per request.
- Resting threads register every connection of busy threads: a registration and a wake per request.
- Shared poller, nested exclusive wake, rescuer thread: measured above.

## Follow-up

The 50 ms HTTP/2 sweep and the Windows 50 ms park become per-deadline waits.

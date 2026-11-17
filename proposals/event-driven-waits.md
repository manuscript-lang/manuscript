# Replace periodic looks with kernel timers

**Status: not adopted** (PR 4238 closed unmerged, 2026-11-16; Chinmay kept the periodic look). Kept as the record of what was measured; see the wiki page on connection stealing, "Rejected, do not retry".

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

## Measurements (2026-11-16, 4 vCPU shared VM, alternated runs; three binaries: `main` at 9f09fd55, PR 4227's watcher, this design)

Each cell is the range over 3 runs (2 for TLS and HTTP/2); CPU is process user plus system seconds for the run.

| Scenario | `main` | 4227 watcher | Kernel timers, T = 250 µs |
| --- | --- | --- | --- |
| Fixture `http-long-handler-does-not-hold-others` | 30 of 30 | 30 of 30 | 20 of 20 |
| Fast mix 4000 req/s (40k requests): CPU | 2.67 to 2.89 s | 2.67 to 2.85 s | 2.99 to 3.02 s |
| Fast mix p50 / p99 | 0.66 ms / 1.7 to 2.2 ms | 0.66 ms / 1.9 to 2.5 ms | 0.67 ms / 2.1 to 2.2 ms |
| Slow mix 2000 req/s: CPU | 9.4 to 9.8 s | 9.5 to 9.6 s | 8.8 to 9.1 s |
| Slow mix p50 / p99 | 0.61 to 0.65 ms / 2.4 to 3.3 ms | 0.61 to 0.63 ms / 2.4 to 2.9 ms | 0.65 ms / 2.7 to 3.0 ms |
| TLS slow mix: CPU / p50 / p99 | | 9.9 s / 0.63 ms / 3.4 ms | 9.3 s / 0.67 to 0.69 ms / 3.3 to 3.7 ms |
| HTTP/2 slow mix: CPU / p50 / p99 | | 10.5 s / 0.71 to 0.73 ms / 3.7 to 3.9 ms | 10.0 to 10.1 s / 0.78 ms / 3.7 to 3.9 ms |
| Closed loop, 64 conns, req/s | 128k to 137k | 133k to 140k | 122k to 128k |
| Idle, 4 threads, 6 keep-alive connections, 1 s | | | 91 µs CPU, 1 context switch (fixture `http-idle-server-stays-asleep`) |

Reading: the slow-mix tail is the same as the watcher's and CPU is 3 to 7% lower, with TLS and HTTP/2 covered. Two costs remain, both small: fast-mix CPU is 8 to 10% above both (about 11 µs per request), and the closed loop is 3 to 7% below the watcher (within the machine's spread, but consistently lower in three of three pairs). The p50 is 20 to 60 µs higher at the slow mix.

### Where the fast-mix CPU goes

- `strace -c` at the fast mix: 3.6 `timerfd_settime` calls per request (an arm when a thread leaves rest and a disarm when it rests: 1.8 rest cycles per request), 0.17 timer reads per request under `strace` and fewer than 500 fires in 40,000 requests without it. Fires on merely busy threads are negligible.
- A variant with every hook and counter in place but the two timer calls removed costs nothing (2.4 to 2.6 s). So the whole difference is the timer calls.
- A C loop of `timerfd_settime` arm plus disarm on this VM takes 5.2 µs per pair (5.7 µs with the timer registered in an epoll set): programming a one-shot hrtimer is a VM exit here. On hardware without that exit it is far cheaper; it was not measured because no such machine is at hand.
- Cut already: no arm while the thread lists no waiting connection (a connection listed later in the stretch starts the clock then).
- Not possible without breaking the guarantee: dropping the disarm lets a rest longer than T end in a stale fire that wakes a peer, which at this load is most rests; skipping the arm on a guess about run length misses the first long handler after a run of short ones.
- What remains is two system calls per rest cycle and nothing else.

### Choice of T

| T | Fast mix CPU | Slow mix CPU | Slow mix p99 | Slow mix p50 |
| --- | --- | --- | --- | --- |
| 100 µs | 3.3 to 3.5 s | 10.0 to 10.3 s | 4.0 to 4.7 ms | 0.66 to 0.70 ms |
| 250 µs | 3.0 to 3.3 s | 9.1 to 9.5 s | 3.8 to 4.0 ms | 0.67 to 0.71 ms |
| 1 ms | 2.8 to 3.3 s | 8.5 s | 3.9 to 5.7 ms | 0.74 to 0.83 ms |

(One alternated sweep, 3 fast and 4 slow runs each, on a busier machine than the table above, so compare within it.) A shorter T fires on more threads that are only busy and costs CPU as 1/T; a longer one leaves a ready request waiting that much longer behind a held-up thread (p50 and p99 rise). 250 µs is where both are near their floor. It is also about 10 times a request's service time (about 25 µs), so a handler that finishes in the usual time never fires its timer.

### Dead ends measured on the way

- A, one shared one-shot poller that every thread waits on: 0 to 20% throughput loss (microbenchmark of epoll, owned vs shared).
- A2, `EPOLLEXCLUSIVE` on a nested epoll descriptor: `EINVAL`.
- B, kernel readiness lent to one rescuer thread (the first implementation): one wake per request, about 14 µs of CPU each, 20% of closed-loop throughput.
- A "turn counter unchanged" test alone is wrong: the event that reports a request also wakes its owner. "Has not rested since arming" is the test.

### Platform notes

- Linux: `timerfd`, nanosecond resolution.
- macOS: a `kqueue` of its own per timer, registered in the helper's `kqueue`, with `EVFILT_TIMER` in nanoseconds (`NOTE_NSECONDS`) and `NOTE_CRITICAL` so the kernel does not coalesce a short deadline. Written with `libc` directly because `rustix` 1.1.5 encodes a sub-millisecond timer as zero seconds. `libc` is already a dependency of five sibling crates. Verified by CI only.
- Windows: a high-resolution waitable timer (`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`, about 0.5 ms; an ordinary timer ticks at 1 to 15.6 ms) with a thread-pool wait that wakes the helper's `mio` poll. So on Windows the effective T is the timer's resolution, a latency of up to about 0.5 ms more than Linux. Verified by CI only.

## Inventory (2026-11-16, `main` at 9f09fd55)

| Kind | Where | Value | Verdict |
| --- | --- | --- | --- |
| Periodic look | `ms-rt/src/watch.rs` | 100 µs while a hook asks, 2 ms otherwise, sleeps after 20 quiet looks | Kept: not adopted, see the wiki decision page |
| Periodic look | `http/server/steal.rs` `BALANCE_EVERY` | 10 ms | Remove: balance on count change |
| Periodic look | `http/server.rs` H2 sweep | 50 ms while any HTTP/2 connection lives | Follow-up PR (HTTP/2 stealing): per-stream deadlines |
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

# Closing what containers and fields own: no cost without resources

A record, alternative, `Optional`, `List` or `Map` closes the resources it holds when its scope ends ([proposal](../../../proposals/close-owned-parts.md)). A holder of values that are not resources must pay nothing for that: its class stays `Copy` or `Move`, no binding is registered, and the lowering emits no closer.

[`run.sh`](run.sh) checks it: it lowers every `ms.toml` project under `bench/perf` with a compiler from before the change and one with it, in the same directory, and compares the lowered MIR (`ms emit`) and the linked binaries byte for byte.

```sh
git worktree add /tmp/base 8f2c47fe9 && (cd /tmp/base && cargo xtask runtime && cargo build --release --locked -p ms-cli)
make build
sh bench/perf/close-parts/run.sh /tmp/base/target/release/ms ./target/release/ms
```

## 2026-10-28

- Base: `8f2c47fe9` (main, #1874). Head: the change that adds this page. Both `ms` 0.1.0 Release builds (LLVM backend).
- Machine: Intel Xeon @ 2.80GHz, 4 vCPUs, 15 GB RAM, Linux 6.18 (shared cloud VM).

| project | lowered MIR | binary |
| --- | --- | --- |
| closure-capture, competence, csv, datastructures, json, kernels, listloops, programs, strappend, toml, web, workers | identical | identical |
| web/fetch | differs | differs |
| stdlib | not lowered by either compiler as a project | |

12 of 13 projects are byte-identical, so their speed is the speed of the base compiler and needs no separate timing. `web/fetch` differs because it holds a resource: its `Fetcher` has a hand-written `close` and an `HttpClient` field, and its scope end now also closes that field (`close_parts` calls `Fetcher.close`, then `HttpClient.close`; the second close of an already closed client is a no-op). That is the feature, not a cost on plain values.

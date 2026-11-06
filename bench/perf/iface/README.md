# Interface calls

ns per call of a one-method interface in a 50 M iteration loop: a direct loop, a value built in the loop's function, one returned by a callee, and one passed to a function that makes the calls.

## Run

```sh
cargo xtask runtime && cargo build --release --locked -p ms-cli
target/release/ms build bench/perf/iface/main.ms -o /tmp/iface
/tmp/iface   # one line per case: name, ns per call, checksum
```

## 2026-11-06: Linux x86_64

Intel Xeon @ 2.10 GHz, 4 vCPUs, release (LLVM). Three alternating runs of `00e968fc`: every case is 0.30 to 0.32 ns, equal to the direct loop.

A prototype MIR pass rewrote `call.method` on a receiver defined by `iface.new`, `iface.borrow` or `iface.view` into a direct call of the vtable thunk (and let the inliner take method thunks). It changed nothing here and nothing in `streams` (medians of 5 alternating runs, within noise: `stream-map` 20.5 to 20.0, `stream-map3` 37.7 to 37.2, `source-map` 2.6 to 2.7). It was not merged: LLVM already resolves these calls from the readable vtables ([wiki](../../../wiki/compiler/llvm-resolves-interface-calls-from-vtables-it-can-read.md)), and the unoptimized Cranelift build runs no MIR passes.

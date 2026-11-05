+++
title = "Lowering"
weight = 2
+++

# Lowering

Inspect generated calls and drops to review an agent’s lowering change (repository root).

```sh
target/release/ms emit examples/hello/ms.toml -o hello.mir
sed -n '21,32p' hello.mir
```

```text
fn @main() -> int export !0:4:8 {
b0:
  depth.enter
  %0: str = str "Arguments: " !0:5:5
  %1: list<str> = call @arguments () !0:5:5
  %2: int = list.len %1 !0:5:5
  %3: str = call.rt @msrt_int_to_string (%2) !0:5:5
  %4: str = call.rt @msrt_string_concat (%0, %3) !0:5:5
  %5: str = str "\n" !0:5:5
  %6: str = call.rt @msrt_string_concat (%4, %5) !0:5:5
  drop %4 !0:5:5
  drop %3 !0:5:5
```

- The MIR excerpt shows calls and temporary-value drops.
- Alpha: MIR and native layouts may change.

<span id="defaults-belong-to-the-callee"></span>
<span id="equality-and-keys"></span>
<span id="implementation-scope"></span>
<span id="source-locations-and-fault-frames"></span>
<span id="typed-values"></span>

Next: [calls](function-calls.md), [representations](value-representations.md), [evaluation](evaluation-order.md), [cleanup](cleanup-and-faults.md), and [lowering design](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md).

# Exact template numeric comparisons

Build `ms build main.ms --build-type Release -o template-numbers`, then time
alternating baseline and candidate executions. Each invocation validates its
answer and returns nonzero on error; use the same compiler/backend for both.

```sh
./template-numbers 123 456 '<' 100000
./template-numbers 1.25 2.5 '<' 100000
./template-numbers 1.25 1.2500 '==' 100000
./template-numbers 1.0000000000000000001 1.0000000000000000002 '<' 100000
./template-numbers -1.25 -0.5 '<' 100000
./template-numbers 1e400 2e400 '<' 100000
./template-numbers 1e-400 2e-400 '<' 100000
```

Also compare long common coefficient prefixes. Integer-only controls bypass the
general exact-number path and cannot establish fractional performance. Keep
run-specific measurements outside this reusable fixture.

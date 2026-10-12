+++
title = "Standard-library tests"
weight = 5
+++

# Standard-library tests

Standard-library fixtures in `tests/e2e/testdata/stdlib/*.ms` use Manuscript test blocks to exercise codecs, numeric boundaries, Unicode, collection mutation, formats, optional budgets, files, scheduling, and loopback networking. The native harness builds and runs them through checked declarations and runtime dispatch.

```sh
make stdlib-check
make stdlib-test E2EFLAGS=-count=1
```

`stdlib-check` checks source and requires test blocks for every public module. `stdlib-test` executes those blocks and expected-fault transcripts. Individual fixtures can run with `ms test tests/e2e/testdata/stdlib/encoding.ms`.

Network tests use loopback sockets; filesystem tests use temporary directories. TLS tests use a public fixture key and fixed certificate. Runtime unit tests cover native boundaries and cancellation races. Linux, macOS, and Windows checks exercise platform behavior with native dependencies bundled in the compiler distribution.

Keep expected behavior in the source fixtures. A declaration-only fixture establishes acceptance; a runtime contract needs an executed assertion. See the [development workflow](development.md) for full validation.

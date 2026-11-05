+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Preview the checks required to validate an agent’s compiler patch (repository root).

```sh
make -n check
```

```text
cargo xtask runtime
cargo xtask symbols --check
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
```

- Remove `-n` to execute; `make verify-full` adds the broader gates.
- Alpha: changed contracts need regression tests.

<span id="conformance"></span>
<span id="continuous-integration"></span>
<span id="generate-the-standard-library-reference"></span>
<span id="preview-and-publish-the-book"></span>
<span id="rust-unsafe-boundary"></span>

Next: [check targets](https://github.com/manuscript-lang/manuscript/blob/main/Makefile), [conformance instructions](https://github.com/manuscript-lang/manuscript/blob/main/tests/conformance/README.md), and [release maintenance](maintenance.md).

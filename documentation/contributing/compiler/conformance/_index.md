+++
title = "Compiler conformance"
weight = 3
+++

# Compiler conformance

Conformance tests check language rules through accepted and rejected source and observable runtime behavior.

- [Semantic tests](semantic-tests.md), including cancellation and cleanup

Keep the smallest program that demonstrates a rule. Accepted and rejected modules live under `tests/conformance/fixtures/e2e/` (`accept/cl-*.ms` and neighbors); the frozen corpus in `tests/conformance/` also records expected command output. Run the focused example first, then the broader checks in the [development workflow](../../development.md). If prose and a fixture disagree, check the canonical language rule and implementation before changing either.

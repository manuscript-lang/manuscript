+++
title = "Compiler conformance"
weight = 3
+++

# Compiler conformance

Conformance tests check language rules through accepted and rejected source and observable runtime behavior.

- [Semantic tests](semantic-tests.md), including cancellation and cleanup

Accepted and rejected core-language modules live as fixtures under `tests/e2e/testdata/` (`accept/cl-*.ms` and neighbors); the fixtures, not prose, are the source of truth.

Run the current checks as described in the [development workflow](../../development.md).

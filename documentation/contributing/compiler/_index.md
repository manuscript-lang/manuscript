+++
title = "Compiler internals"
weight = 4
+++

# Compiler internals

For compiler contributors. Start with the [pipeline and passes](pipeline.md), then [parsing and checking](frontend/_index.md) and [lowering](lowering/_index.md). [Conformance tests](conformance/_index.md) specify accepted source, rejected source, and runtime behavior.

To investigate a wrong result, first reduce it to a program and run the [semantic test workflow](conformance/semantic-tests.md). If checking succeeds but execution is wrong, compare the lowered MIR with the source evaluation and ownership rules. Application build settings live in [builds and projects](../../developer-tooling/builds/_index.md).

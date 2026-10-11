+++
title = "Debugger transport and source interpretation"
weight = 120
+++

# Debugger transport and source interpretation

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The debugger combines native Go execution control with Manuscript-aware rendering of values, tasks, and generated frames.

Delve DAP provides native debugger transport; a Manuscript debugger layer renders source values and marks generated cleanup and runtime frames. Native line mapping alone does not provide that interpretation.

[Delve DAP](https://github.com/go-delve/delve/blob/master/Documentation/api/dap/_index.md)

## Inspecting parallel, Background, and with

The required debug conformance program steps through API admission, concurrent operations, joining, and cleanup. It must demonstrate source stepping, value rendering, and operation and service inspection together; native line mapping alone cannot establish that behavior.

See [complete-program evidence](../../compiler/conformance/programs.md), [metadata](metadata.md), and [Go line mapping](source-mapping.md).

[Previous: Generated Go source mapping](../debugging/source-mapping.md)

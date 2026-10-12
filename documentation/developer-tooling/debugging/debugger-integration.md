+++
title = "Debugger transport and source interpretation"
weight = 120
+++

# Debugger transport and source interpretation

The debugger design has two parts: Go tools control execution, while a Manuscript layer explains source values, concurrent operations, and generated frames. A native line number alone cannot explain a source alternative or a cleanup frame.

Delve DAP provides native debugger transport; a Manuscript debugger layer renders source values and marks generated cleanup and runtime frames. Native line mapping alone does not provide that interpretation.

[Delve DAP](https://github.com/go-delve/delve/blob/master/Documentation/api/dap/_index.md)

## Inspecting TaskGroup, Scheduler, and with

The required debug conformance program steps through API admission, concurrent operations, joining, and cleanup. It must demonstrate source stepping, value rendering, and operation and service inspection together; native line mapping alone cannot establish that behavior.

See [complete-program evidence](../../contributing/compiler/conformance/programs.md), [metadata](metadata.md), and [Go line mapping](source-mapping.md).

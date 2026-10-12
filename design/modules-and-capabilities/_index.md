+++
title = "Modules and capabilities"
weight = 75
+++

# Modules and capabilities guide

[Design index](../_index.md)

Organize code into files, choose what each file exports, and pass external services into the functions that need them. A capability is an object that grants access to a service such as files or the network. Adapter pages explain the planned bridge to foreign code.

## Reading order

### 1. [Module boundaries](modules/_index.md)

- [Modules, exports, and imports](modules/declarations.md)
- [Boundary contracts](modules/boundaries.md)

### 2. [Authority and effects](capabilities/_index.md)

- [Explicit capability authority](capabilities/authority.md) — Make file, network, and other external access visible in function inputs.
- [Inferred effects and call relationships](capabilities/effects.md) — Follow external behavior through a function and the functions it calls.

### 3. [Foreign adapter contracts](adapters/_index.md)

- [Adapter manifests](adapters/manifests.md) — Declare a foreign adapter API and the facts the compiler trusts.
- [Foreign values and the trust boundary](adapters/value-conversion.md) — Validate foreign values before they enter Manuscript.
- [Foreign cancellation and resource acquisition](adapters/cancellation.md) — Arrange for foreign calls and resource acquisition to respond to stopping.

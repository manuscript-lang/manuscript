[Wiki](../index.md) › [Language](index.md)

# Interfaces convert implicitly; construction is removed

Status: in flight (PR #1135, not yet on main as of this note). Decision: a value converts to an interface at a typed binding or argument (`let v: Shape = x`), and `Shape(value: x)` / `Shape(x)` fail with "cannot be constructed"; about 260 stdlib and fixture uses were migrated. Re-check the checker before relying on either spelling.

Apply when: touching interface views, generic matching, or conversion diagnostics.

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md)

+++
title = "Go lowering units"
weight = 21
+++

# Go lowering units

`pkg/lower` lowers a checked program in independent units so lowering scales with cores and a change stays local.

- **Unit.** One function instance: a function or method at concrete type arguments. A unit reads the checked program, which is immutable, and owns its scratch state (`gen`: substitution, temporaries, captured bindings).
- **Registry.** `shared` interns instances, types, and helper functions (`equal_T`, `format_T`) once, under a mutex. The first unit to need an item builds it; others only use its name. A unit never reads another unit's output while it runs.
- **Waves.** `assemble` lowers the functions discovered so far in parallel, then merges their results in the order they were first requested and queues the functions they need. Output order is discovery order and does not depend on scheduling. Nothing is sorted.
- **Names.** A generated name derives from the source name and type arguments, plus a hash of the identity where several declarations share a source name (`duplicateNames`). It never depends on which unit ran first. Two identities claiming one name fail lowering.
- **Located statements.** Source-line labels are numbered during the merge, so the numbering follows output order.

Rules for new lowering code: keep per-unit state on `gen`, put anything shared in `shared` behind `mu`, record dependencies with `touch`, and build shared items inside `building` so their dependencies attach to the item. Run `go test -race ./pkg/lower` when changing any of this.

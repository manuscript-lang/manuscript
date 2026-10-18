+++
title = "Go lowering units"
weight = 21
+++

# Go lowering units

`pkg/lower` lowers a checked program in independent units, so lowering scales with cores and changes stay local.

- **Unit:** one function instance at concrete type arguments. It reads the immutable checked program and owns its scratch state (`gen`).
- **Registry:** `shared` interns instances, types, and helpers (`equal_T`, `format_T`) once, under a mutex. A unit never reads another's output while running.
- **Waves:** `assemble` lowers discovered functions in parallel, merges results in first-requested order, and queues new needs. Output follows discovery order, never scheduling.
- **Names:** derived from source name and type arguments, plus an identity hash where declarations share a name (`duplicateNames`). Two identities claiming one name fail lowering.
- **Located statements:** line labels are numbered during the merge.

New lowering code keeps per-unit state on `gen`, puts shared state in `shared` behind `mu`, records dependencies with `touch`, and builds shared items inside `building`. Run `go test -race ./pkg/lower` after changes.

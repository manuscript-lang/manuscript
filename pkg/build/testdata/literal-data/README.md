# Independent literal constructor oracle

`program.ms` and `before.go.txt` were captured with a self-contained `ms` built
from pristine main `f01d88003284cc21ffda49284b04694c53f8cd8a`, before #147's
checker or lowering changes, using the pinned Go 1.25.1 SDK. The CLI used Release
and a separate empty `MANUSCRIPT_CACHE_DIR`; `before.go.txt` is the actual native
workspace `main.go`. No candidate emitter generated this oracle.

- `program.ms` SHA256: `db188e2ca7089e9e1146c33a22937174a0d0750843191948e094a64de2371319`
- `before.go.txt` SHA256: `c2086ef7502812b744c8db896855f9b0333bb8c210276db43334f7e241de356c`
- First List composite formatted with the pinned Go AST formatter SHA256:
  `14f056a0e496cbba6ff77959a189419ceed5206a63a9ece9b49aa07aae677362`

These match the independently recorded original #272 oracle exactly. The
eligible optimized constructor now changes intentionally; hash the frozen
baseline and compare executable results/source directives separately. Preserve
this oracle and the pre-AST `testdata/go-ast` baseline when output evolves.

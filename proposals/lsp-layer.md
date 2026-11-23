# Move the language server into its own `src/lsp` layer

## Problem

`src/cli/` holds 18,492 lines; 6,212 of them are the language server (`lsp_*`, 32 files). The server shares no code with the
command line beyond four helpers (`json_value`, `findings`, `snippet`, `checked_input`), and `main.c` reaches it through one
call (`ms_lsp_command`). Layer rules cannot say that the server must not depend on build, run or package code, and the `cli`
owner reviews a third of its directory as unrelated work.

## Proposed change

- New layer `lsp` in `src/layers.txt`: `lsp: base abi compiler tooling`; `cli` gains `lsp` in its allowed list.
- `git mv src/cli/lsp_*` to `src/lsp/`; `cmake/targets/lsp.cmake` builds `ms_lsp`; `ms` links it.
- `json_value`, `findings`, `snippet` and `checked_input` move to `src/tooling/`: they are shared by the server and the
  commands, so they sit in the layer both may include. `ms_tooling` now links `ms_project` and `ms_own` for `checked_input`.
- `OWNERS`, `src/README.md`, AGENTS.md and the wiki page for the server name the new path.

No behavior change: files move and includes change; no function body is edited.

## Evidence

The include scan shows lsp files include only base, abi, compiler and tooling headers, plus the four helpers above; no lsp file
includes a runtime or cli header, and `main.c` is the only cli file including an lsp header. `ms_lint` enforces the new rule, so
the boundary cannot erode.

## Alternatives considered

- Do nothing: keeps the owner and layer rules blunt; the cost is review noise, not a defect. Chinmay chose the move.
- Keep the four helpers in `cli` and let `lsp` include `cli`: makes `lsp` a sibling that depends on its caller's layer.
- Make the helpers a new layer: four small files do not justify a layer; `tooling` already holds inspection and lint results.

## Testing

`ctest --preset ci`, `lint`, `conform`, `conform-commands`, `repo-check`; `lsp_session` replays an `ms lsp` session.

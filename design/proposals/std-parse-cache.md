# Parse the bundled standard modules once per language-server session

## Summary

- Problem: every language-server check parses each bundled standard module it loads again, about a fifth of a keystroke's check, though the sources are fixed per binary.
- Change: `MsStdCache` parses every bundled module once, into one arena with one frozen name table. A check's own `MsNames` is layered over that table (`ms_names_init_over`) and reuses the parsed trees. Only `ms lsp` opts in.
- Decision requested: none; no language or output change.

## Status

Built, from the language-server thread's request to cache the parsed modules in `load_std_module`.

## Problem

The server builds a fresh `MsNames`, graph and program per analysis, so each one parses its std modules and interns their identifiers again. A session of 30 edit-then-hover rounds on a small file (release build, callgrind, whole process): 4.88G instructions, about 163M per analysis.

## Design

- `MsNames` gains an optional frozen `base`. A base text keeps its id; a new text gets the next id after the base's, so ids stay dense and `ms_names_count` still sizes id-indexed arrays. The base is only read, so any number of layered tables may share it, on any thread.
- `check/std_cache.c` parses all bundled modules once with the base table and indexes the trees by the id of `@std/<name>`. `load_std_module` takes the cached tree when the program has a cache and the path is in it; a module that failed to parse is left out and takes the old path, so its error is reported as before.
- Checks never write a tree (the only writer, `lazy_std.c`, runs on analysis programs that do not take the cache), so one cache serves every check. `lsp_analysis.c` builds it on first use and keeps it for the session.
- The one-time cost is parsing every bundled module on the first analysis. `ms check`, build and run do not use the cache, since they load few modules once.

## Measured

Same session, same replies (byte for byte): 4.88G to 3.94G instructions, -19%; wall 1.09 s to 0.85 s including startup and the one-time parse.

## Alternatives considered

- Do nothing: a fifth of every keystroke stays on re-parsing fixed text.
- Cache by interning into a growing session-wide `MsNames`: user identifiers accumulate for the life of the server, and the table cannot be read from two analyses at once.
- Parse std modules lazily into the cache: the shared table would need a lock or a mutable base; parsing all of them once is simple and bounded.
- Snapshot the parsed trees at build time: a stable serialized AST is a large new layer for the same win.

## Testing

`ctest` 33/33 (the language-server session replays are the check that replies are unchanged), a unit test for layered names (`value_unit`), and the session above compared byte for byte against a build without the cache.

# Checker scratch never goes in the checker arena

- `MsCheck.arena` lives as long as the checker, and the test tools (and a language server) keep one checker over thousands of files. Anything allocated there per call is kept forever. `lower-diff.sh` reached 13 GB this way (#5497).
- Scratch (visit marks, candidate lists, distance tables) goes in a local `MsArena` freed before returning; only the result is copied to the checker arena.
- Never allocate "one entry per row of a table" per call: the tables grow with every file. A property of an interned type row is computed once when the row is added (`MsTyTable.open`, read by `ms_ty_has_variable`), since a row's parts are rows already.
- mimalloc is force-included, so valgrind's massif shows nothing. To find a leak, break on `arena_add_chunk` in gdb, print the arena and a short backtrace, and group by arena: the arenas with few distinct addresses and many chunks are the long-lived ones.
- What still grows (about 0.24 MB per file) is each file's own module in the shared checker. Making it flat needs a checkpoint and rollback of `MsCheck`, which is a proposal of its own.

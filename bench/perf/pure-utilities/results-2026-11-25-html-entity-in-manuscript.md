# HTML character references moved from C to Manuscript (2026-11-25)

Change: `runtime/std/html.c` and `html_entity.c` (about 1,000 lines of C, 2,231 named references) became `stdlib/internal/html_entities.ms`, which `data/html.ms` calls for `escape`, `unescape` and the tokenizer's text and attribute decoding. The three `msstd_html_*` externs are gone. Proposal: [pure codecs in Manuscript](../../../design/proposals/pure-codecs-in-manuscript.md), stage 2.
Baseline: `d810e9f0`. After: this branch. Same program, same preset, same shared 4-core Linux x86-64 VM, no other build running, 31 alternating runs, 100000 rounds of `unescape` and `escape` over four strings (references of every kind, a long plain run, a run of 40 `&amp;`). Wall time in ms for the whole run.

| | before (C) min / median | after (Manuscript) min / median | ratio |
| --- | --- | --- | --- |
| unescape + escape | 574 / 610 | 592 / 635 | 1.03 / 1.04 |

Callgrind instructions (3000 rounds): 167.5M before, 257.8M after (1.54x); wall time is closer because the C spends its time in `memchr`-style byte loops and a string builder, which the port replaces with the same loops over views.

Output check: `projects/html_oracle` replays 8,214 cases recorded from the C code (every named reference, the legacy no-semicolon forms, attribute and text mode, numeric forms and their limits, mixtures); every output is identical.

The first port was 1.5x to 1.65x and, with an integer table, over 60x. Findings, in the order they cost time:

- A module constant that is a list (`ENTITY_KEYS`, 2,231 integers) was rebuilt, copied and freed on every read: 36 s for this run. The MIR already had `list.const.view` (a borrowed view of static data, from the old [constant-list-view](../../../design/proposals/constant-list-view.md) proposal) and nothing lowered to it. `lower_list.c` now lowers a reference to a list of integer literals to that op; a use that keeps or changes the list clones it. Fixture: `accept/constant-list-view.ms`.
- Reading a name's first 8 bytes as one integer (`Bytes.int64_be`) costs a `Result` and a native call per step, so the sorted keys are an integer constant and the search compares integers, with a byte compare only for names of 8 bytes or more.
- A binary search per first letter (53 bounds) instead of over all rows; no `view` per name (the search takes offsets into the input).

Reading: the table is a 96 KB text constant in `html_entities.ms`, one fixed-width line per reference, so the checker and lexer pay once and the binary holds it as read-only data.

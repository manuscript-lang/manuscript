# A split loop walks the text and makes no list

Verified (2026-11-25): `for line in data.split("\n")` built a list of every piece (16 bytes each, 22 MB log: 400,001 pieces and 16 MB, 3.6k page faults) and then walked it once. Lowering now reads the piece that starts at byte offset `i` with `msrt_string_split_at(text, sep, i)` and steps by the piece length plus the separator length, the way the `chars` walk steps by scalar width (`lower_for.c`, `source_split`). The loop runs while `i < text.length + (separator is not empty)`: a non-empty separator ends in an empty piece, an empty one cuts after each scalar and ends with the text. The pieces are views of the text, as `split_view`'s are, so the extern has role `MR_VIEW_RESULT`; without it the copy-elision pass turned `piece.clone()` of a dying piece into a move and the clone viewed freed text (`e2e/stdlib/split-view-clone-outlives-source`).

Wall time, min of 9 (22 MB `access.log`): grep 44.5 to 35.1 ms (Rust 26.8), report 186.6 to 150.4 (Rust 118.2), treegrep 32.6 to 25.8, logstats 53.3 to 48.2, sortrecords 287.5 to 245.3. Page faults fall to the read-only level (grep 9.4k to 5.7k, report 31k to 18k) and the resident set by 15 MB. Callgrind instructions rise on the split-heavy programs (grep +11%, treegrep +11%, pargroup +4.8%, report +2.3%) because each piece is a call that re-reads both strings: the loop is memory bound, so the trade is a win. A one-byte separator skips `ms_needle_for`.

The list form stays for everything else: `parts := text.split(..)` kept in a variable, `.split(..)` passed on, and every other producer (`fields_by`, `lines`, `map`, `filter`). Those need the builder-loop fusion of #7039.

Apply when: a list is built by a runtime call and read once by a counted loop; look for the same split of the producer into a state that fits in one integer.
Evidence: `src/compiler/lower/lower_for.c`, `src/runtime/core/string_split.c`, `e2e/accept/split-loop-reads-pieces-in-place`, `bench/perf/suite/results.md`.
Verify: `ctest`, `conform`, valgrind on a loop whose receiver is a temporary; page faults and wall time of grep and report.

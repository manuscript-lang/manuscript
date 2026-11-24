[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A one-scalar string is always inline and a clone is an operation

Verified (2026-11-24, `bench/perf` instruction counts against checked C): `wordfreq` 4340M to 2994M (-31%), `dedupe` 1334M to 1159M (-13%).

- `scalar_text` returned a phi of a constant inline string (ASCII) and a runtime call, so LLVM could not fold the tag checks of the three `c == " "` compares in `fields_by`: 54 instructions per character. The fast path now builds both words from the scalar's bytes and length (a scalar is at most four bytes, so it is always inline), with the tag constant. A phi over string kinds hides constants from LLVM; a phi over words does not.
- `String.clone()` lowered straight to `call.rt @msrt_string_clone`, which copyelim never sees. It is now the language `clone` op (`fn_native_call`), lowered to the same call in `lower_ops`, so a copy of a last use is a move. Anything the optimizer should reason about must stay an op until `lower_ops`.
- A stack-framed closure whose captures own nothing needs no `drop` (`drop_empty_framed_closures`); the call was 28 instructions, twice per `Map.update`.
- `Map.entries()` did a hash lookup per key (`for key in self.keys() { self[key] }`). Consuming `values()` in order, moving each value, costs one clone fewer than indexing both lists (indexing deep-copied every value twice: jsonrt +10%).
- The single-caller inline allowance of 400 (#6855) inlines `callback_places` into its closure in `list-incoming-resource-transfer` and the unwinder then mishandles the fault path (#6870); it stays at 25 until that is fixed (csvgroup 1110M with 400, 1220M with 25). Corpus failures did not fail CI at the time, so run `conform` before declaring a perf change safe, and never read a FAIL line in CI output as a timing flake.
- `sweep.sh` copies of the `ms` binary may resolve a different runtime; compare runtime-affecting changes by building in the tree (`cnt.sh`).

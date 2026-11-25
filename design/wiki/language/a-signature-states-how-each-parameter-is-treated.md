# A signature states how each parameter is treated

Rule (owner, 2026-11-24): a signature states everything a caller needs; bodies are checked against signatures, never read by callers.

- A parameter borrows its argument unless the signature says `move`. A body that returns, binds or stores a resource or generic parameter without `move` is an error (`ms_own_taken_report`, `src/compiler/own/taken.c`). Before this the compiler inferred the mode from the body, and about 100 stdlib and test signatures had to gain `move`.
- Not yet removed, still read from bodies: whether a function-typed parameter is kept or held by the result (`escapes.c`), which parameters a result is part of (`result_borrows.c`; choice for the owner, see the measured counts in the thread: 949 stdlib functions return owned without `move`, 46 return a borrow), closer facts and effect reach (lint only).
- Reject fixture: `e2e/reject/signature-must-say-move-for-a-kept-parameter`. The report skips `var` and function-typed parameters on purpose.
- Once the report is clean, the inferred `taken` mask only duplicates the declared `move` flags, so the pass can be deleted.

Decision (owner, 2026-11-24, `design/proposals/argument-modes-in-signatures.md`): two marks answer two questions. `hold` on an argument says the result keeps using it (frozen until the result's last use); `&T` in a type says a value is a reference to something owned elsewhere. An unmarked result is a new owned value, so result `move` is deleted. Rejected after discussion: consume by default with `&` on parameters (93% of parameters are plain reads, so nearly every one would carry it), `hold` on record fields (the `&` type says it), always-owned results, lifetime labels (add only if a real case needs two sources). Stage 2a parses `hold`; it has no checker meaning until the stacked stages land.

Decision (owner, 2026-11-25): a function is not an owned value. A function-typed parameter takes no `move` or `hold`, and `&fn` does not exist; both are errors. The compiler decides closure ownership from what the callee does with the function (`escapes.c`: kept, held, and a name handed to a callee that holds it in a kept result), and an extern function keeps what it is handed. `&T` is written with no space. Result `move` is deleted; a bodied function's mask is only what its signature states.

Lesson (dropping `Clonable`, 2026-11-25): a bodied `&T?` result of a heap `T` lowers as an owned copy (boxed Optional, `borrows_result`), so `List.find`/`min`/`max` and `Set.find` still need `Clonable` until [#6937](https://github.com/manuscript-lang/manuscript/issues/6937) is fixed; `&T?!` results (`random.choice`, `weighted_choice`) borrow correctly. Revisit those stdlib signatures after the fix.

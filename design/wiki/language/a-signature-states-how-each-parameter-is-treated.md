# A signature states how each parameter is treated

Rule (owner, 2026-11-24): a signature states everything a caller needs; bodies are checked against signatures, never read by callers.

- A parameter borrows its argument unless the signature says `move`. A body that returns, binds or stores a resource or generic parameter without `move` is an error (`ms_own_taken_report`, `src/compiler/own/taken.c`). Before this the compiler inferred the mode from the body, and about 100 stdlib and test signatures had to gain `move`.
- Not yet removed, still read from bodies: whether a function-typed parameter is kept or held by the result (`escapes.c`), which parameters a result is part of (`result_borrows.c`; choice for the owner, see the measured counts in the thread: 949 stdlib functions return owned without `move`, 46 return a borrow), closer facts and effect reach (lint only).
- Reject fixture: `e2e/reject/signature-must-say-move-for-a-kept-parameter`. The report skips `var` and function-typed parameters on purpose.
- Once the report is clean, the inferred `taken` mask only duplicates the declared `move` flags, so the pass can be deleted.

# A string held in a slot is appended in place

Verified (2026-11-23): `b += f"line {i}\n"` over 200,000 iterations took 40 s because the variable lived in a slot (an owned value that a faulting call outlives is slot-held with a cleanup) and the append was `load`, `concat`, `take`, `drop`, `put`: a full copy per append. The SSA form (`s += "ab"`) was always in place, so the `append` guard never showed it. `strfuse` now runs again at the start of the late steps and `lift_slot_take` moves the `take` in front of the concat, so the existing fusion grows the string in place: 40 s to 9 ms, and `bench/perf/suite/gen.ms` no longer runs for 20 minutes. The first run of `strfuse` cannot see this because the slot's drop is still a call to the close function until inlining.

The first version cost `strings` +2.7% instructions: an append of an inline (non-owned) receiver went through the owned-block path for nothing. `msrt_string_append` now sends a receiver that owns no block to `msrt_string_concat`; `strings` is -0.5% against main.

Moving the second run late exposed `msrt_bytes_concat_grow` returning a view unchanged for an empty piece; `Bytes.clone` is `concat(self, self.view(0, 0))`, so the clone aliased a freed block. It copies a view now.

Apply when: a loop that builds a string or bytes is slow at large sizes (time 25k, 50k, 100k; doubling should roughly double), or a pass changes how a variable's drop is emitted.

Two gaps found later (2026-11-24, yaml `quoted` and `plain_continuation`, which took 20 G and 2 G instructions for 100k characters and made the yaml tests take 31 s; now 170 M and 5 s). The slot load may sit in an earlier block than the concat (the piece came out of an inlined call), so `lift_slot_take` accepts it when no path between them touches the slot. And `mir_extern_intern` kept the first caller's declaration, so a program whose missing-key fault text interned `msrt_string_concat` without the `string_concat` role first lost the role for every later concat, and `strfuse` saw no concat at all; the role of a later caller now fills an empty one. A pass that keys on an extern's role depends on this: test it after a role-less caller has interned the extern (`string-append-after-missing-key-fault.ms`).

Compile-time note (2026-11-24): `lift_slot_takes` once recomputed `mir_use_counts` for every block, which was 19% of `ms emit --opt` on a yaml program; it counts once per function and again only after a lift. Callgrind counts a `rep stosb` memset per byte, so zeroing looks bigger there than in wall time; measure with both.

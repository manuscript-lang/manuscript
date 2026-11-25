# An index in range is one unsigned compare, before the negative fix-up

Verified (2026-11-25): a checked `list.get/set/fill/addr` computed `index < 0 ? index + len : index` on every access, then compared it unsigned with `len` (cmp, cmov, add, cmp: about 8 instructions with the select). `mir_expand` now tests `index <u len` first and goes on with the index itself; only an index outside that range takes a slow block that adds `len` and checks again. With a fault exit the access is repeated in a block per path and both join with the lowering's fault flag. Callgrind against main: interp -10.1%, graph -5.5%, sim -4.4%, nothing else beyond +-0.5% except `workers` +8.5% (see below).

`workers` (`hist[x % 256] = hist[x % 256] + 1`) got slower: the old select-form index was identical for the get and the set, so LLVM merged them to one check; the two branch forms are not merged. A pass that drops the second check of the same `(list, index)` after a checked access would fix it and gain on every read-modify-write.

Apply when: changing how `list.get`-style ops expand; a single comparison on the hot path is the target, and a select on the index defeats it. Verify with `ms emit --opt` (verifies every pass) and conform: fixture `list-index-counts-from-the-end.ms` covers negative, in-range and both out-of-range ends for get and set.

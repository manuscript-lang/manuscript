[Wiki](../index.md) › [Testing and conformance](index.md)

# Random programs with a Python model find ownership bugs the corpus misses

Verified (bug bash, 2026-11-18): hand-written probes and the corpus found two crashes; three small generators found more in minutes. Each writes a program from a grammar and the expected output from a Python model of the language rule: paths into temporaries (`top().mids[0].opt.get().xs[0]` bound, printed, listed, passed), borrow-returning calls over parts of temporaries, random resource moves/branches/loops with exact close order, and list-of-resource operations. About 15% of the call-over-temporary programs printed garbage before the copy-removal fix; the drop-order and list generators found nothing in about 1,300 programs.

Apply when: changing copy removal, temporary handling in lowering, or the borrow verifier. Write a generator for the construct (a dozen lines of grammar plus the model) and run a few hundred programs in Debug and Release, then `tools/leak-check.ms` on a sample.
Evidence: the internal error "implicit copies of a borrow" for a nested list element of a temporary (`tests/conformance/fixtures/e2e/accept/bind-part-of-temporary.ms`); `MS_EMIT_OPT=1 ms emit file.ms` shows the optimized MIR where a clone was removed before its source was dropped.
Verify: a failing program prints garbage or a `compiler produced invalid code` error; its optimized MIR has a `drop` before the last use of a borrowed value.

Bug bash 2026-11-19: about 3,000 accepted random programs over moves, borrows, closures, returned parts, temporaries and `var` interface calls found nothing, and the checker rejected every unsound variant tried by hand. That generator is now `tools/ownership-fuzz.ms` (`make ownership-fuzz SEED=n COUNT=n`, nightly): it needs no model because every value prints as `<prefix><n>-<letters>`, so a borrow that read freed storage prints something else; it also compares Debug with Release and fails on a live block at exit. Extend its `step` table when a new ownership construct lands.

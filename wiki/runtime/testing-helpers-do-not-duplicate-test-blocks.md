[Wiki](../index.md) › [Runtime](index.md)

# Testing helpers do not duplicate test blocks

Decision: the user removed `describe` and `it` callback helpers because wrapping those steps in an existing `test` block duplicates grouping without creating independently selectable or reported cases. Keep assertions directly usable in ordinary test blocks; do not restore these wrappers without a new direction.


Apply when: adding BDD helpers or test suite grouping.
Evidence: the user's explicit removal request; [testing declarations](../../stdlib/test/test.ms).
Verify: standard testing exports contain assertions, fail and skip, with no callback suite wrappers.

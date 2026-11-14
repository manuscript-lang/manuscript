[Wiki](../index.md) › [Repository maintenance](index.md)

# Fixes address the root cause, not a name or shape

Decision (Chinmay, 2026-11-14): no hacky fixes. A fix must not be a special case keyed on a function or type name, a particular op shape, or one benchmark or test input. Such fixes pass the case that exposed them and leave the bug in every neighbor.

- Find where the wrong behavior starts and fix that general layer; derive behavior from declarations, not name lists.
- If only a hack fits, stop and report the root cause on the issue instead of shipping the hack.
- A deliberate temporary workaround is different: it gets an issue naming its removal condition and is deleted once the fix lands.

Apply when: fixing any bug or perf gap, or reviewing a fix.
Evidence: [fix-issue](../../skills/fix-issue/SKILL.md), [simplify](../../skills/simplify/SKILL.md).
Verify: the diff has no string compare on a function name, no check of one benchmark's op sequence, and a regression test for a second shape.

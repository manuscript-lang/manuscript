[Wiki](../index.md) › [Testing and conformance](index.md)

# Expectations live in the test file, after the program

Decision: a conformance `check` fixture states its diagnostics as trailing `// expect-error:` lines in its own `.ms` file, not in a sidecar JSON (`tools/conform/expect.ms`). The lines go after the program because a line added above it shifts every position, in the expectation and inside messages such as "at 7:5". The rendered terminal text and byte offsets are not stored; both derive from stored fields. Record with `--record --inline`; do not hand-write positions you have not observed.

Apply when: adding a rejected program, or converting another fixture kind to the inline form (parse, run and test follow in the staged plan).
Evidence: [proposal](../../proposals/readable-conformance-tests.md), [corpus README](../../../tests/README.md), `tools/conform/expect_test.ms`.
Verify: `make conform` replays inline and sidecar fixtures with equal counts; `lint` reports a leftover sidecar as an expectation without a fixture.

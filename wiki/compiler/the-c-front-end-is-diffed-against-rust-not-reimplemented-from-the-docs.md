[Wiki](../index.md) › [Compiler and build](index.md)

# The C front end is diffed against the Rust one, not rewritten from the docs

Verified: `compiler/` ports `ms-syntax` stage by stage. Messages, positions, fixes and token boundaries equal the Rust front end's byte for byte, including odd ones (a CRLF source, `{:?}` quoting of a non-ASCII character, node ids in allocation order). The corpus has too few error cases for that, so `make c-compiler-test` also compares mutated copies of every `.ms` file; a first port of the lexer passed the whole corpus and 30,000 mutants, which found nothing to fix, but a mutant run is what catches a missed message.

Apply when: changing `compiler/src`, `crates/ms-syntax/src/{lexer,parser,dump}.rs`, or the oracle `crates/ms-syntax/examples/c_oracle.rs`. A change to the Rust front end changes the oracle: port it to C in the same change, or the comparison fails.
Evidence: [compiler/README.md](../../compiler/README.md), `compiler/tests/syntax-diff.sh`.
Verify: `make c-compiler-test` prints `ok` for every mode and set.

The checker follows the same rule. `compiler/tests/check-diff.sh` compares the C checker's tables with `crates/ms-check/examples/c_oracle.rs`, and each pass the C checker gains adds a comparison line there (diagnostics, then types, interface evidence, ownership facts, effect sets) before its Rust code is deleted. The tables are one type table plus dense symbol columns (`compiler/include/ms/tables.h`), not a tree of reference-counted types; a pass adds columns indexed by the same ids.

`ms_effect_facts` (`effect_facts.c`) builds the reference graph of a module from the scan and the directive lines of each callable (the module's own text, library text from `mods[m].text`), resolves it, and returns per function the declared effects it reaches, its `allow_effect` patterns and the callables its body names. A function whose graph reaches a body the scan cannot read (a method or interface call, an unchecked library body) is `partial`; the review facts must print that, never an empty list. `check-diff.sh` compares `reach` and `permits` on the claimed, non-partial functions.

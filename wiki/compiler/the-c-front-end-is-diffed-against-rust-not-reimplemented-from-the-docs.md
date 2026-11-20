[Wiki](../index.md) › [Compiler and build](index.md)

# The C front end is diffed against the Rust one, not rewritten from the docs

Verified: `compiler/` ports `ms-syntax` stage by stage. Messages, positions, fixes and token boundaries equal the Rust front end's byte for byte, including odd ones (a CRLF source, `{:?}` quoting of a non-ASCII character, node ids in allocation order). The corpus has too few error cases for that, so `make c-compiler-test` also compares mutated copies of every `.ms` file; a first port of the lexer passed the whole corpus and 30,000 mutants, which found nothing to fix, but a mutant run is what catches a missed message.

Apply when: changing `compiler/src`, `crates/ms-syntax/src/{lexer,parser,dump}.rs`, or the oracle `crates/ms-syntax/examples/c_oracle.rs`. A change to the Rust front end changes the oracle: port it to C in the same change, or the comparison fails.
Evidence: [compiler/README.md](../../compiler/README.md), `compiler/tests/syntax-diff.sh`.
Verify: `make c-compiler-test` prints `ok` for every mode and set.

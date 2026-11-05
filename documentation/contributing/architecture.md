+++
title = "Repository architecture"
weight = 1
+++

# Repository architecture

Locate the compiler stages in this checkout (repository root).

```sh
git ls-files crates/ms-{syntax,check,lower,mir,clif}/Cargo.toml
```

```text
crates/ms-check/Cargo.toml
crates/ms-clif/Cargo.toml
crates/ms-lower/Cargo.toml
crates/ms-mir/Cargo.toml
crates/ms-syntax/Cargo.toml
```

- Alpha: crate boundaries may change.
- Use checked identities rather than reconstructed names.

<span id="follow-one-compilation"></span>
<span id="keep-shared-behavior-in-one-implementation"></span>
<span id="keep-source-and-generated-output-distinct"></span>
<span id="know-what-each-crate-owns"></span>
<span id="make-a-change-where-its-behavior-lives"></span>
<span id="read-the-evidence-correctly"></span>

Next: [crate responsibilities](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) and [development checks](development.md).

[Wiki](../index.md) › [Tooling and docs](index.md)

# Effects are implicit-deny comment directives

Decision: the owner chose a function effect system with no grammar change. A function is pure unless `// ms: allow_effect PATTERN` permits what it reaches; `// ms: effect NAME` declares an effect. Exported stdlib functions declare `std.`-prefixed names, bodies unscanned; externs and internals are never marked and purity is never declared. There is no `deny_effect`, no `contain_effect` and no value conditions; an interface value is the chokepoint for rooted access (`FileTree`).

Apply when: touching effect directives, MSL116, stdlib tags or `ms review` effect rows. Authority is charged where obtained (closure literal, function value, interface conversion, generic instantiation), not where called. A function's own lines only tighten its file header. Rollout is a warning first, an error at a later release.

Evidence: [proposal](../../proposals/function-effects.md), `crates/ms-check/src/effect_reach.rs`, `crates/ms-tooling/tests/lint_effects.rs`.
Verify: `cargo test -p ms-tooling --test it lint_effects`; `ms lint` on a helper that calls `print` reports MSL116 with the path.

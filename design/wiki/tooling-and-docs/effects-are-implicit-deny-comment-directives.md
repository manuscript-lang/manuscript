[Wiki](../index.md) › [Tooling and docs](index.md)

# Effects are implicit-deny comment directives

Decision: the owner chose a function effect system with no grammar change. A function is pure unless `// ms: allow_effect PATTERN` permits what it reaches; `// ms: effect NAME` declares an effect. Exported stdlib functions declare `std.`-prefixed names, bodies unscanned; externs and internals are never marked and purity is never declared. There is no `deny_effect`, no `contain_effect` and no value conditions; an interface value is the chokepoint for rooted access (`FileTree`).

Apply when: touching effect directives, MSL116, stdlib tags or `ms review` effect rows. Authority is charged where obtained (closure literal, function value, interface conversion, generic instantiation), not where called. A function's own lines only tighten its file header. Rollout is a warning first, an error at a later release.

Implicit dispatch is charged too: `==` and `!=` charge the operand type's own `equals`, and a method whose receiver declares an `Equal`, `Hashable` or `Comparable` bound on a type argument (a `Set` or `Map` key included) charges that type's own `equals`, `hash` or `compare` (#3977). Ordering operators take no user type.

Evidence: [proposal](../../proposals/function-effects.md), `src/compiler/check/effects_reach.c`, `src/tooling/lint_effects.c`.
Verify: `ctest --preset ci`; `ms lint` on a helper that calls `print` reports MSL116 with the path.

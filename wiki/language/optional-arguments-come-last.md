[Wiki](../index.md) › [Language](index.md)

# Optional arguments come last

Decision (Chinmay, 2026-11-15): a parameter or constructor field with an explicit default may not precede a required one. The checker rejects it (`required x follows optional y`). `T?` parameters default to `none` without being written and stay free of the rule, so a nullable value can sit among required ones. `HttpResponse(status, body, headers)` is the model.

Apply when: adding a function, method or record to the stdlib or examples. Native `extern` signatures are not checked; they mirror the Rust symbol.
Verify: [positional-arguments.ms](../../tests/conformance/fixtures/e2e/accept/positional-arguments.ms), and the `required_parameters_and_fields_may_not_follow_an_explicit_default` unit test in `ms-check`.

[Wiki](../index.md) › [Language](index.md)

# Infer local callback signatures from context

Decision: the user explicitly permits callback parameter and result inference. Known function contexts supply omitted parameter types; callback bodies can supply generic output evidence after inputs are known, including success types within a partially known Result context. Named public signatures stay explicit; function-type identity uses ordered parameter types and the result, without parameter names.

Apply when: changing callback checking, generic inference, syntax or editor annotations.
Evidence: [callback rules](../../documentation/core-language/functions/function-values-and-closures.md#contextual-callback-inference), [contextual callbacks fixture](../../tests/e2e/testdata/accept/contextual-callbacks.ms). Expected-result evidence: [inference rules](../../documentation/core-language/types/generics.md#inference-from-arguments), [contextual generics fixture](../../tests/e2e/testdata/accept/contextual-generics.ms), and [inference module](../../crates/ms-check/src/inference.rs).
Verify: source and native callbacks cover generic map results, callbacks listed before their inference inputs, optional callbacks, nested closures, constructors, and editor parameter navigation.

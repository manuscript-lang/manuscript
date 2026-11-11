[Wiki](../index.md) › [Language](index.md)

# Method values borrow their receiver

Decision: a method value (`re.find_all`, `log.error[Unit]`) is a closure over its receiver and follows the closure rules. While it stays local it borrows the receiver's place, so the receiver stays readable and unchangeable until the value's last use; when it is stored, returned or passed to a moving parameter it takes the receiver, moving it at its last use (a receiver used again needs `.clone()`). A `Copy` receiver or a temporary one is held by value. The old lowering copied the receiver into every method value, which a value with one owner (a `Regex`, a `Logger` holding one) cannot survive once refcounts are gone.

Mechanism: the ownership walk records `bound_borrows` for a non-escaping method value of a place (`method_value_use`, `changing_method_use` in `walk.rs`); the binding holds a `Borrow` of the receiver's places like a lambda binding, and a later move of the binding marks the value escaping through `meta.lambda` in the usual fixpoint. Lowering (`method_receiver` in `closure.rs`) captures the receiver's address, the variable's own slot or a frame slot holding the borrowed value, and the thunk loads it; the interface, default-parameter and native thunks share the address-holding variants that `var fn` method values already used. A specialized method value `value.method[T]` is an `Apply` node whose `value` may read as an expression, so detect it with `info(e).native_str() != "index"`, not with `value: None`.

Apply when: changing how function values hold receivers or captures, or adding a thunk kind for method values.
Evidence: [function values](../../documentation/core-language/functions/function-values-and-closures.md), [ownership notes](../../crates/ms-check/OWNERSHIP.md), `tests/conformance/fixtures/e2e/stdlib/regex-spans.ms` ("span methods support bound calls"), `tests/conformance/fixtures/e2e/stdlib/log.ms` ("levels filter methods and function values").
Verify: `find := re.find_all_spans` followed by `re.capture_spans` works with no copy under `MS_COPY_PROBE=1`; `holders.append(re.find_all)` followed by a use of `re` is rejected as a move.

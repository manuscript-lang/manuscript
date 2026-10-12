+++
title = "Plain-language glossary"
weight = 1
+++

# Plain-language glossary

[Book index](_index.md)

Use this page when the guide uses an unfamiliar term. Follow a link for the exact rules and examples.

| Term | Meaning in this guide |
| --- | --- |
| [Binding](core-language/basics/bindings.md) | A name attached to a value. `let` prevents reassignment; `var` allows a replacement value. |
| [Scope](core-language/basics/bindings.md#scope-and-shadowing) | The part of a program where a name is visible. Nested blocks create nested scopes. |
| [Module](modules-and-capabilities/modules/declarations.md) | One `.ms` source file. It imports and exports individual declarations. |
| [Record](core-language/types/records.md) | A value with named fields, such as a customer with a name and email. |
| [Nominal type](core-language/types/records.md) | A type identified by its declaration. Two records with identical fields can still be different types. |
| [Alternative](core-language/types/alternatives.md) | A type with a fixed set of cases. A value is one case at a time and may carry that case's data. |
| [Contract / interface](core-language/types/contracts.md) | A declared set of operations an implementation must provide. |
| [Generic parameter](core-language/types/generics.md) | A placeholder for a type, such as `T` in `List[T]`. |
| [Bound](core-language/types/generics.md) | A requirement on a generic type, such as supporting equality or concurrent sharing. |
| [Intrinsic / prelude](standard-library/types/prelude.md) | The small set of types and compiler bounds available without imports. |
| [Result](core-language/errors/results.md) | Either a success value or an expected error value. Callers can handle or forward the error. |
| [Optional](core-language/types/optionals.md) | Either a present value or `none`. Absence does not carry an error explanation. |
| [Fault](core-language/errors/faults.md) | A programming failure, such as a false assertion. It ends the current operation after cleanup. |
| [Closure / capture](core-language/functions/function-values-and-closures.md) | A function value that keeps the surrounding values it uses. Captured bindings are snapshots. |
| [Alias](ownership-and-cleanup/values/references.md) | Another reference to the same object. Closing a resource affects every alias. |
| [Resource lifetime](ownership-and-cleanup/_index.md) | How long a file, connection, or other external resource remains open and usable. |
| [Shareable](ownership-and-cleanup/values/sharing.md) | Safe to access concurrently. It does not keep a resource open. |
| [Capability / authority](modules-and-capabilities/capabilities/authority.md) | A passed-in object that permits external operations, such as file or network access. |
| [Effect](modules-and-capabilities/capabilities/effects.md) | External behavior reachable from an operation, such as reading, writing, or calling a service. |
| [Operation / group](concurrency/joining.md#terms) | One invocation started by a concurrency API / the invocations started by one parallel call. |
| [Join](concurrency/joining.md) | Wait until every started operation has finished, including its cleanup. |
| [Execution context](concurrency/_index.md#fixed-lifetimes) | Runtime state carrying an operation's cancellation signal and deadline. The runtime passes it internally. |
| [Cancellation checkpoint](concurrency/cancellation.md#propagation-and-checkpoints) | A point where work checks whether it should stop and unwind. |
| [Unwind](ownership-and-cleanup/cleanup/exit-order.md) | Leave active scopes and run their registered cleanup. |
| [Shielded cleanup](ownership-and-cleanup/cleanup/cleanup-faults.md) | Cleanup that can run despite the cancellation or deadline that ended ordinary work. |
| [Host](standard-library/hosts/_index.md) | The runtime entry point that runs a CLI application or handles HTTP requests. |
| [Adapter](modules-and-capabilities/adapters/_index.md) | A declared bridge between Manuscript and foreign code, such as Go. |
| [Typed IR](compiler/frontend/typed-ir.md) | The compiler's internal program representation after names and types have been checked. |
| [Lowering](compiler/lowering/_index.md) | Translating checked Manuscript operations into generated Go while preserving their behavior. |
| [Conformance](compiler/conformance/_index.md) | Tests and evidence that the implementation follows the language's rules. |
| Normative | Defines a required rule. Other explanations and examples must agree with it. |

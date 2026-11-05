+++
title = "Plain-language glossary"
weight = 1
+++

# Plain-language glossary

Unfamiliar term? Follow its link for exact rules.

| Term | Meaning in this guide |
| --- | --- |
| [Binding](core-language/basics/bindings.md) | A name attached to a value. `let` prevents reassignment; `var` allows a replacement value. |
| [Scope](core-language/basics/bindings.md#scope-and-shadowing) | The part of a program where a name is visible. |
| [Module](core-language/modules/declarations.md) | One `.ms` source file. It imports and exports individual declarations. |
| [Type](core-language/types/named-types.md) | A value with named fields, such as a customer with a name and email. |
| [Opaque type](core-language/types/named-types.md#opaque-types) | A type whose fields stay hidden outside the file that declares it; other files use the functions it exports. |
| [Nominal type](core-language/types/named-types.md) | A type identified by its declaration. Two types with identical fields can still be different types. |
| [Enum (alternative)](core-language/types/alternatives.md) | A nominal tagged union declared with `enum`, with a fixed set of cases. A value is one case at a time and may carry that case's data. |
| [Contract / interface](core-language/types/contracts.md) | A declared set of operations an implementation must provide. |
| [Generic parameter](core-language/types/generics.md) | A placeholder for a type, such as `T` in `List[T]`. |
| [Bound](core-language/types/generics.md) | A requirement on a type parameter, such as supporting comparison or supplying a particular operation. |
| [Equal](core-language/types/equality-and-hashing.md) | A standard interface for comparing values with `==`, `!=`, or `equals`. |
| [Hashable](core-language/types/equality-and-hashing.md) | A standard interface for computing lookup hashes. Map keys and set elements must also implement Equal. |
| Prelude | Names available without imports, including `Optional`, `Result`, `Error`, `print`, and the standard equality interfaces. |
| [Result](core-language/errors/results.md) | Either a success value or an expected error value. Callers can handle or forward the error. |
| [Optional](core-language/types/optionals.md) | Either a present value or `none`. Absence does not carry an error explanation. |
| [Fault](core-language/errors/faults.md) | A programming failure, such as a violated invariant. It ends the current operation after cleanup. |
| [Closure](core-language/functions/function-values-and-closures.md) | A function value that keeps the surrounding values it uses. |
| [Own](core-language/types/references.md) | The binding, field, or collection slot responsible for dropping a value. A move transfers that responsibility; replacing an owned value drops the old one. |
| [Borrow](core-language/types/references.md#borrowing) | Access to a value another holder owns, without taking it: shared (`let`, plain argument) or exclusive (`var`). It ends at its last use. |
| [Move](core-language/types/references.md) | Ownership transfers to a new holder at the value's last use. The old name is dead until reassigned. |
| [Clone](core-language/types/named-types.md#mutation-and-cloning) | `.clone()`: the only explicit, deep duplicate of an owned value. Numbers and other plain values copy implicitly. |
| [Capture](core-language/functions/function-values-and-closures.md) | A binding used from a surrounding function. Non-escaping closures borrow captures; escaping closures take ownership when created, following the move rules. |
| [Alias](core-language/types/references.md) | Another borrow of the same object. Closing a resource affects every alias. |
| [Resource lifetime](core-language/cleanup/_index.md) | How long a file, connection, or other external resource remains open and usable. |
| [Promise](core-language/concurrency/promises.md) | An operation with one result taken through `wait()`; stream reads may defer work until the wait. Dropping it cancels and waits for completion. |
| [Stream](core-language/concurrency/streams.md) | `ReadStream[T]` produces values over time; `WriteStream[T]` accepts them. Reads obtain the next item; built-in writers buffer immediately, and flushing follows the destination’s backpressure rule. Custom stream operations may wait. |
| [Pipe](core-language/concurrency/streams.md) | An in-memory reader and writer for transferring values between promises. |
| Capability / authority | A service object that permits external operations, obtained through a host accessor or passed to a helper. |
| [Effect](developer-tooling/source/effects.md) | External behavior reachable from an operation, such as reading, writing, or calling a service. |
| Join | Wait until every started operation has finished, including its cleanup. |
| [Cancel signal](core-language/concurrency/promises.md#waiting) | A signal attached through `PromiseOptions` so a `Cancel` can request that several promises stop. |
| [Cancellation checkpoint](core-language/concurrency/promises.md#cancellation) | A wait where cancellation can stop work and run cleanup. A loop that never waits must check a cancel signal itself. |
| [Unwind](core-language/cleanup/scopes.md#cleanup-order) | Leave active scopes and run their registered cleanup. |
| [Shielded cleanup](core-language/cleanup/cleanup-faults.md) | Cleanup that can run despite the cancellation or deadline that ended ordinary work. |
| [Host](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/runtime-conventions.md#host-escalation) | The runtime entry point that runs a CLI application or handles HTTP requests. |
| [Typed IR](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/frontend/typed-ir.md) | The compiler's internal program representation after names and types have been checked. |
| [Lowering](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/lowering/_index.md) | Translating checked Manuscript operations into native code while preserving their behavior. |
| [Conformance](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/conformance/_index.md) | Tests and evidence that the implementation follows the language's rules. |
| Normative | Defines a required rule. Other explanations and examples must agree with it. |

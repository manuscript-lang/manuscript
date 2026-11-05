+++
title = "Plain-language glossary"
weight = 1
+++

# Plain-language glossary

Use this glossary while reading the tour, language chapters, or command help. Each term describes Manuscript usage; follow the link for examples and exact rules.

## Programs and values

| Term | Meaning in Manuscript |
| --- | --- |
| [Program and entry point](learn/getting-started.md) | Source compiled into an executable. An exported `main` function starts a command-line program and returns its integer exit status. |
| [Declaration](core-language/modules/declarations.md) | Introduces a named function, type, interface, constant, or other module member. |
| [Expression](core-language/basics/expressions.md) | Code that computes a value, such as `price * quantity` or a function call. |
| [Statement](core-language/basics/syntax.md) | A step in a block, such as introducing a binding, assigning a value, or returning from a function. |
| [Type](core-language/types/compatibility.md) | The compiler-visible kind of a value. It determines which operations and uses are accepted. |
| [Type inference](core-language/basics/bindings.md) | The compiler determines a type from context, such as `Int` for `let count = 3`. Inference does not make the value dynamically typed. |
| [Literal](core-language/basics/syntax.md) | Source notation for a value, such as `3`, `true`, or `"hello"`. |
| [Function](core-language/functions/declarations-and-calls.md) | A named operation with typed inputs and a result. A call supplies inputs and runs its body. |
| [Parameter and argument](core-language/functions/declarations-and-calls.md) | A parameter is an input named in a function declaration; an argument is the expression supplied at a call. |
| [Argument label](core-language/functions/declarations-and-calls.md#argument-names) | A parameter name written at a call, such as `count: 3`, to identify which input an argument supplies. |
| [Return type](core-language/functions/declarations-and-calls.md) | The type a function promises to produce. `return` leaves the function with a value of that type. |
| [Unit and Never](core-language/functions/declarations-and-calls.md) | `Unit` has the single value `unit` and represents no useful result. `Never` describes an operation that does not return normally. |
| [Field](core-language/types/records.md) | A named part of a record value. |
| [Case and payload](core-language/types/alternatives.md) | An enum case names one possibility. Its payload is the data carried by that possibility. |
| [Pattern and exhaustiveness](core-language/control-flow/pattern-matching.md) | A pattern selects values and can bind their parts. An exhaustive `match` covers every possible input. |
| [Method and receiver](core-language/types/contracts.md) | A method is an operation in an implementation. The receiver is the value before the dot at a call, available as `self` in the method. |
| [Implementation](core-language/types/contracts.md) | An `impl` block supplies a type's own methods or its declared implementation of an interface. |
| [Specialization](core-language/types/generics.md) | Using a generic function or type with particular type arguments. Bounds are checked for those arguments. |
| [Import alias](developer-tooling/builds/project-configuration.md) | A configured prefix for locating modules, such as a project library path. This is distinct from borrowing a value through another name. |
| [Diagnostic](developer-tooling/source/diagnostics.md) | A compiler or tool message describing a problem, its location, and a possible repair. |
| [Static checking](developer-tooling/_index.md) | Checking source before running it. It establishes the checked language rules, while tests exercise the behavior of selected inputs. |
| [Native executable](developer-tooling/builds/build-levels.md) | A compiled program for a particular operating system and architecture. It runs without the `ms` compiler installed. |
| [Test](learn/testing.md) | Executable checks of expected behavior, expressed in a `test` block. Failed expectations return errors to the test runner. |
| [Manifest](developer-tooling/builds/project-configuration.md) | The project's `ms.toml` configuration, including its entry point and aliases. |

## Language, ownership, and libraries

| Term | Meaning in this guide |
| --- | --- |
| [Binding](core-language/basics/bindings.md) | A name attached to a value. `let` prevents reassignment; `var` allows a replacement value. |
| [Scope](core-language/basics/bindings.md#scope-and-shadowing) | The part of a program where a name is visible. |
| [Module](core-language/modules/declarations.md) | One `.ms` source file. It imports and exports individual declarations. |
| [Record](core-language/types/records.md) | A value with named fields, such as a customer with a name and email. |
| [Opaque type](core-language/types/records.md#opaque-types) | A type whose fields stay hidden outside the file that declares it; other files use the functions it exports. |
| [Nominal type](core-language/types/records.md) | A type identified by its declaration. Two records with identical fields can still be different types. |
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
| [Owner](core-language/types/references.md) | The binding, field, or collection slot responsible for dropping a value. A move transfers that responsibility; replacing an owned value drops the old one. |
| [Borrow](core-language/types/references.md#borrowing) | Access to a value another holder owns, without taking it: shared (`let`, plain argument) or exclusive (`var`). Ordinary borrows end at their last use; [promise captures](core-language/concurrency/promises.md#reading-and-changing-shared-values) can keep a borrow until the promise holder's scope ends. |
| [Move](core-language/types/references.md) | Ownership transfers to a new holder at the value's last use. The old name is dead until reassigned. |
| [Clone](core-language/types/records.md#mutation-and-cloning) | `.clone()`: the only explicit, deep duplicate of an owned value. Numbers and other plain values copy implicitly. Resources and values containing them cannot be cloned. |
| [Capture](core-language/functions/function-values-and-closures.md) | A value from a surrounding scope used by a closure. Non-escaping closures borrow captures; escaping closures take ownership when created, following the move rules. |
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
| [Unwind](core-language/cleanup/exit-order.md) | Leave active scopes and run their registered cleanup. |
| [Shielded cleanup](core-language/cleanup/cleanup-faults.md) | Cleanup that can run despite the cancellation or deadline that ended ordinary work. |
| [Host](contributing/runtime-conventions.md#host-escalation) | The runtime entry point that runs a CLI application or handles HTTP requests. |
| [Typed IR](contributing/compiler/frontend/typed-ir.md) | The compiler's internal program representation after names and types have been checked. |
| [Lowering](contributing/compiler/lowering/_index.md) | Translating checked Manuscript operations into native code while preserving their behavior. |
| [Conformance](contributing/compiler/conformance/_index.md) | Tests and evidence that the implementation follows the language's rules. |
| Normative | Defines a required rule. Other explanations and examples must agree with it. |

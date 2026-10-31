[Wiki](../index.md) › Compiler and build

# Compiler and build

Checking, lowering, MIR, Cranelift, build, fault sites.

The Go implementation (generated Go, Go runtime, Go toolchain bundling) has been deleted; only the Rust and Cranelift implementation remains. Lessons that were specific to emitting or building Go are gone. What remains is what still constrains checking, lowering, and module loading.

## Pages

- [The implementation is Rust and Cranelift under a value-semantics model](the-implementation-is-rust-and-cranelift-under-a-value-seman.md): the compiler, runtime, standard library, and tools use Rust with Cranelift under a value-semantics memory model.
- [Generic instances resolve contract evidence in the instantiating module](generic-instances-resolve-contract-evidence-in-the-instantia.md): a module-local `impl` is visible only in its module, but a generic function from another module is instantiated with the caller's evidence for its bounded type variables, while operations on concrete…
- [Lowering must honor checker conversions and avoid probing with side effects](lowering-must-honor-checker-conversions-and-avoid-probing-wi.md): checking can attach an implicit conversion (for example Optional wrapping of a plain argument) while the expression keeps its payload type.
- [Evaluation order: receivers and operands are captured before later calls](evaluation-order-receivers-and-operands-are-captured-before.md): a plain local read is not ordered against a later call unless the lowering orders it.
- [Checked Int arithmetic is language behavior](checked-int-arithmetic-is-language-behavior.md): `Int` arithmetic faults on overflow ([design contract](../crates/DESIGN.md)).
- [Native omissions are declared in the standard declaration](native-omissions-are-declared-in-the-standard-declaration.md): defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions.
- [Fault locations name the failing operation's statement, without columns](fault-locations-name-the-failing-operation-s-statement-witho.md): the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs scope-end cleanups in reverse order before aborting ([design contract](../crates/DESIGN.md)).
- [Omitted library entries must stay empty through module loading](omitted-library-entries-must-stay-empty-through-module-loadi.md): executable manifests require an entry; libraries omit the key, and an explicitly empty or invalid entry remains an error.
- [Lowering lends what the checker already holds as a borrow](lowering-lends-what-the-checker-already-holds-as-a-borrow.md): a container read the ownership checker holds as a lexical borrow (`let x = m.get(k)`, `if let x = xs.first()`, `m.get(k).get()`, `m.get_or(k, d)`) must not copy the entry.
- [Compiler passes use the right algorithm and data structure for their input size](compiler-passes-use-the-right-algorithm-and-data-structure-f.md): the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases.

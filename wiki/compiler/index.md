[Wiki](../index.md) › Compiler and build

# Compiler and build

Checking, lowering, MIR, Cranelift, build, fault sites.

- [Callback adapters do not change generic type identity](callback-adapters-do-not-change-generic-type-identity.md): reader conversion applies at a callable value boundary; implementation overlap and receiver matching preserve nested callback modes.

- [Checked Int arithmetic is language behavior](checked-int-arithmetic-is-language-behavior.md): `Int` arithmetic faults on overflow ([design contract](../../crates/DESIGN.md)).
- [Compiler passes use the right algorithm and data structure for their input size](compiler-passes-use-the-right-algorithm-and-data-structure-f.md): the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases.
- [The LLVM backend is its own crate and needs only MIR](the-llvm-backend-is-its-own-crate-and-needs-only-mir.md): `ms-mir-llvm` emits its own symbols and data and depends on no Cranelift code.
- [Error is an indirect record, one pointer wide](error-is-an-indirect-record-one-pointer-wide.md): `T!` was 12 words; boxing `Error` cuts fallible frames by about 190 B.
- [Evaluation order: receivers and operands are captured before later calls](evaluation-order-receivers-and-operands-are-captured-before.md): a plain local read is not ordered against a later call unless the lowering orders it.
- [Fault locations name the failing operation's statement, without columns](fault-locations-name-the-failing-operation-s-statement-witho.md): the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs scope-end cl…
- [Generic instances resolve contract evidence in the instantiating module](generic-instances-resolve-contract-evidence-in-the-instantia.md): a module-local implementation (history; `impl` is gone) was visible only in its module, but a generic function from another module is instantiated with the caller's evidence f…
- [Lowering borrows what the checker already holds as a borrow](lowering-borrows-what-the-checker-already-holds-as-a-borrow.md): a container read the ownership checker holds as a lexical borrow (`x := m.get(k)`, `if x := xs.first()`, `m.get(k).get()`, `m.get_or(k…
- [Lowering must honor checker conversions and avoid probing with side effects](lowering-must-honor-checker-conversions-and-avoid-probing-wi.md): checking can attach an implicit conversion (for example Optional wrapping of a plain argument) while the expression keeps its payload type.
- [`ms-check` exposes only its `api` module](ms-check-exposes-only-its-api-module.md): the one public surface, where to widen it, and the crate-layering check in `ms-repo-check`.
- [Moves and closes work on the owner's storage, never a copy](moves-and-closes-work-on-the-owner-s-storage-never-a-copy.md): without reference counts a move takes the value out of its local and a close runs on the value where it lives (`close_at_result`, `close_owned_result`, `Func.slot_close`).
- [Native omissions are declared in the standard declaration](native-omissions-are-declared-in-the-standard-declaration.md): defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions.
- [Omitted library entries must stay empty through module loading](omitted-library-entries-must-stay-empty-through-module-loadi.md): executable manifests require an entry; libraries omit the key, and an explicitly empty or invalid entry remains an error.
- [Promises borrow their captures and never change them](promises-borrow-their-captures-and-never-change-them.md): the ownership checker's rule for concurrent code (declared by the `Promise` result type), its known gaps, and the `.wait()` migration fixes.
- [Symbols are indexes ordered by intern order, not text](symbols-are-indexes-ordered-by-intern-order-not-text.md): output that must be alphabetical sorts with `Names::cmp`; `Names::str` text lives until its interner is dropped or a session is released.
- [The implementation is Rust and Cranelift under a value-semantics model](the-implementation-is-rust-and-cranelift-under-a-value-seman.md): the compiler, runtime, standard library, and tools use Rust with Cranelift under a value-semantics memory model.
- [Compile time is spent in Cranelift, LLVM tools and serial passes](compile-time-is-spent-in-cranelift-and-serial-passes.md): measured split of a test-corpus build, the verifier and parallel-pass rules, and what costs next.
- [Compiler change checklist](compiler-change-checklist.md): syntax, checking, lowering, MIR, Cranelift, build, and linking rules to check before editing the compiler.
- [LLVM resolves interface calls only from vtables it can read](llvm-resolves-interface-calls-from-vtables-it-can-read.md): release units carry `available_externally` vtable copies so calls on a known `iface.new` inline.
- [Direct LLVM records above eight leaves are memory, not leaf bags](direct-llvm-records-are-memory-not-leaf-bags-above-eight-leaves.md): one `alloca` of the leaf struct, `memcpy` copies, byte-offset field reads, slots for block parameters.
- [LLVM facts need pointer provenance, and Cranelift alias regions are not markers](llvm-facts-need-provenance-and-cranelift-alias-regions-are-global.md): the deleted translation, why region tags are Cranelift-global, direct-emitter facts, and what blocks vectorization.
- [Structural property bits are not worth a whole-program pass](structural-property-bits-are-not-worth-a-whole-program-pass.md): a typical check makes about 270 property queries, and answers depended on per-file impl visibility.
- [Unwind leaves slot values to an active scope close](unwind-leaves-slot-values-to-an-active-scope-close.md): a value taken from a scope-closed slot must not get its own unwind drop, which would free the receiver before the slot's close runs.
- [Unwind cost grows with the values live to scope end](unwind-cost-grows-with-values-live-to-scope-end.md): in task programs a long Debug function registered cleanups for every live value at every fault point, so code and frame grew with the square of its length and overflowed a 512 KiB task slot.

# One `var` convention: the caller passes the address of a slot

## Summary

- Problem: a `var` parameter or `fn var` receiver reaches the callee as a value copy, so the callee's writes are lost; member assignment and reassignment of owned locals are not lowered either.
- Change: a `var` parameter is a `ptr` to a slot that holds the value; the callee takes the value out at entry and puts the final value back at every exit; the caller owns the slot.
- Decision requested: none (no language change); review of the MIR and emit contract.

## Status

Proposal, 2026-11-22, checked against `main` at the C restart (#5911).

## Problem

`MM_VAR` is set by `param_mode` (`lower_func.c`) but no pass reads it, so a `var` parameter is an ordinary borrowed value:

```ms
type Counter:
	n: Int

fn var Counter.inc() Void:
	self.n = self.n + 1

fn main() Void:
	var c = Counter(n: 1)
	c.inc()
```

- `self.n = ...` fails: "assignment to a member is not lowered yet" (`lower_stmt.c`).
- `var s = "a"; while ...: s = s + "b"` fails verification ("%7 used after it was consumed"): the new value is owned by the loop scope while the variable still refers to it.
- `var l = List[Int](); l.append(4)` loses the write: `call.rt` passes the address of a copy (`rt_argument`, `emit_call.c`).
- Runtime natives (`NS_VEC_MUT`, `NS_STR_MUT`, `NS_MAP_MUT` in `native_sigs.h`) already expect the address of the variable's own storage.

## Design

One rule for calls, vtable thunks, closures and runtime natives:

- A `var` parameter is a MIR parameter of type `ptr`, mode `MM_BORROW`. The pointee is a slot of the declared type that holds an owned value.
- Callee: at entry `take` (`load` for a type without drops) the slot's value into an owned variable; every return, `try` and early return included, goes through `fn_scope_unwind(0)`, which `put`s (`store`s) the variable's final value back. Reads and writes in between are SSA. A closure that captures a `var` parameter is rejected as before (`lower_closure.c`).
- Caller: for a place `P`, `slot` a stack cell, `put` the owned value of `P` into it, pass its address, `take` the value after the call (on every return path, errors included), store it back into `P`. A local name moves its value out and back; a member or element path moves a clone in and `type.set`s the result back.
- Runtime natives: the same slot address is the `ptr` they take; the native writes through it. `rt_argument` already passes a `ptr` operand as is, so emit needs no change for natives.
- `MM_VAR` is unused: a `var` parameter is a `ptr` parameter with mode `MM_BORROW`; the caller passes a `slot` address.
- Vtable thunks (`method_thunk`) keep the erased `ptr` receiver and forward it unchanged for a `fn var` method; the interface value is the slot.
- Owned locals: a `var` local that needs a drop is owned by its variable, not by the scope that created its value. Creation and assignment `scope.disown` the new value; assignment drops the old one; each scope exit emits `scope.own` of the variable's current value just before `scope.end`. A name read in an owning position is already cloned, so no value moves out of a variable.
- Member assignment `a.b.c = v`: take `a` out of its variable, `type.set` along the path (`type.get` for the inner records), put the result back. Index assignment uses `list.set` the same way.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `lower/lower_func.c`, `lower_scope.c` | `ptr` var params, entry `take`, exit `put`; owned-variable registry per scope | conformance e2e `var` fixtures, `ms-c run` of the repro |
| `lower/lower_stmt.c` | member and index assignment, owned reassignment | same |
| `lower/lower_call.c`, `lower_native.c` | caller slot protocol, shared by natives | `List.append` on a `var` |
| `lower/lower_conv.c` | thunks forward the slot | generic interface with a `fn var` method |
| `emit` | none expected | |

## Alternatives

- Do nothing: `var` methods, `List.append` and every mutating collection method stay broken; `fn var` is used throughout `stdlib/collections/collections.ms`.
- Value in, value out (the callee returns the new receiver next to its result): changes every signature and every vtable entry, and cannot express a native that writes through a pointer.
- Heap box for every `var` local: allocates on the hot path; the Rust lowering rejected it for the same reason.

## Stages

1. Owned `var` locals and reassignment (loop repro; independent of slots). Check: `ms-c run`, `ctest`, lint.
2. Member and index assignment. Check: record and list fixtures.
3. `ptr` var params, caller protocol, natives, thunks. Check: `var` fixtures and the run corpus.

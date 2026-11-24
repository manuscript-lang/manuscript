# Specialize self-recursive functions on a known closure

## Summary

- Problem: a recursive function that takes a closure and passes it on (a quicksort with a comparator, a tree walk with a predicate) keeps `call.ind` for every call, because closure specialization skipped any callee on a cycle.
- Change: a callee whose only cycle is a call to itself gets the same private copy as an acyclic one; the copy's recursive call passes the known closure and resolves to the same copy.
- Decision requested: none; no language or visible behavior changes.

## Status

Implemented, 2026-11-23.

## Problem

A stable quicksort written in Manuscript (`quick(buf, ..., cmp, ancestor)` calling itself, `insertion` and `merge_range`) ran every comparison through `call.ind` of the comparator and copied both records into the call. On 200k records the whole program took 308M instructions; with the closure resolved it takes 263M, of which the builtin sort it is compared with is 102M, so the Manuscript sort itself went from 156M to 111M instructions and from 125 ms to 100 ms on 1M records.

## Design

`ic_specializable` rejected every callee on a cycle, so the call that starts the recursion never got a copy. A callee now qualifies when none of its direct callees other than itself is on a cycle (`ic_only_self_recursive`). The copy replaces the closure parameter with a `closure.new` of the same code; its recursive call passes that value, which the next specialization round recognises and redirects to the copy already made for (callee, code, parameter). The size limit and the module budget are unchanged, and mutual recursion is still skipped.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_inline_args.c`, `opt_inline_closure.h` | allow a self-recursive callee | `e2e/accept/closure-specialize-recursive` |
| `design/wiki/benchmarks-and-performance` | lesson | none |

## Alternatives

- Do nothing: every recursive higher-order function pays an indirect call and a by-value record copy per element.
- Specialize mutual recursion too: the copy count multiplies with the cycle; no case needs it yet.
- Inline the comparator into the recursive function by hand in the stdlib: keyed on one function and unavailable to user code.

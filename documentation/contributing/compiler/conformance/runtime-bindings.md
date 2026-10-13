+++
title = "Runtime binding acceptance cases"
weight = 103
+++

# Runtime binding acceptance cases

These fixtures check standard imports and API identities, concurrent sharing, data operations, hosts, and adapter rules. Run each accepted module and each rejected change independently. Use them alongside the [core-language fixtures](core-language.md).

## Standard imports and declaration identity

```manuscript
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Decimal from "@std/decimal.ms"

fn amount() -> Result[Decimal, String]:
    return ok(12.50d)

test "explicit standard imports":
    if not ([1, 2].length() == 2):
        return panic(message: "check failed")
    match amount():
        ok(value):
            if not (value == 12.50d):
                return panic(message: "check failed")
        error(_):
            return panic(message: "Unexpected case")
```

Accept without an `[aliases]` table. Independently remove List and reject its bracket literal; remove Decimal and reject its annotation/literal; remove Result and reject its annotation and expression constructor lookup; remove panic and reject its call. Importing a function must not expose the type names in its signature. Match cases remain available from an inferred scrutinee even when its type name is not imported, as in the [CLI entry fixture](../../../standard-library/cli.md).

Accept this independent module without standard imports:

```manuscript
import panic from "@std/faults.ms"

type List:
    count: Int

type Result:
    case Value(value: Int)

fn compute(value: Int) -> Int:
    return value

fn ordinary() -> Result:
    return Result.Value(compute(value: 3))

test "standard spellings are ordinary names":
    if not (List(2).count == 2):
        return panic(message: "check failed")
    let forward = compute
    if not (forward(value: 4) == 4):
        return panic(message: "check failed")
    match ordinary():
        Value(value):
            if not (value == 3):
                return panic(message: "check failed")
```

Adding the canonical List or Result import rejects its collision with the local declaration. `try ordinary()` is rejected: this Result is not the standard alternative. A bracket literal is rejected without the standard List import even though a local List exists. The local compute function is an ordinary function value.

Preserve ordinary generic method specialization and constructor restrictions in all existing sharing fixtures. Independently reject unimported TaskGroup, Task, Scheduler, ExecutionError, OperationId, StartError, and check_cancelled in otherwise well-formed calls or annotations; importing one standard export must not expose the rest. A local check_cancelled function remains an ordinary function and receives no runtime checkpoint behavior.

Module-resolution cases reject an `[aliases]` entry for `@std`, `@std` without a module path, a missing standard file/export, and paths or symlinks escaping the standard-library directory. Resolving a standard module in two installation directories with identical pinned contents preserves identity; changing its pinned distribution invalidates module/analysis/code-generation caches. Adapter interfaces may import standard declarations but cannot use that exception to import application files. Importing contract types does not obtain service values; explicitly imported host accessors return the current execution's services when called.

## Error adaptation and typed tasks

Run `tests/e2e/testdata/accept/task-groups.ms` for annotated and inferred handles, generic forwarding, stored specialized start/join methods, nested domain Results, repeated joins, retained outcomes after close, empty groups, and zero timeout. Run `task-group-load.ms` for a flat loading example with independent typed results.

Reject Task construction, non-function or nonzero-argument start callbacks, Task result type mismatches, group-join result annotations other than Unit, equality/hashing/cloning of task handles or groups, and unspecialized generic start function values. Direct try in Unit tests remains invalid; helper functions must return the exact Result error type.

For mapping, accept `fn(item: Int) -> Int` and reject an otherwise identical `fn(id: Int) -> Int`. Reject start operations returning Int or plain Unit; accept only `fn() -> Result[Unit, String]`. Use controlled reporter fixtures to verify String errors, crashes, status expiry, bounded overflow fallback, and reporter-fault fallback without recursive reporting.

## Sharing and contract cleanup

```manuscript
import panic from "@std/faults.ms"

import Bytes from "@std/bytes.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"

type ClosedFile:
    marker: Unit

impl File for ClosedFile:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        return error(IoError.Closed)

    fn close() -> Unit:
        return

test "contract-valued cleanup":
    with file = File(ClosedFile(unit)):
        match file.read(max_bytes: 1):
            ok(_):
                return panic(message: "Unexpected case")

            error(cause):
                if not (cause == IoError.Closed):
                    return panic(message: "check failed")
```

This fake represents an already-closed stream, so its close is idempotent and has no external release obligation. Reject `with` over a concrete type merely having a method named close without `impl Closeable`. Reject a contract with the wrong close signature. Verify native and source fake File values are interchangeable through Files.open's `Result[File, IoError]` result.

Accept a function parameter as a TaskGroup callback, a function-bearing record behind a contract view, and callbacks passed through `identity[T]`, fields, returned values, lists, and branch/var merges. Snapshot captures remain unchanged; assignment to an outer captured binding remains rejected.

Accept stored `Scheduler.start` and HTTP serve methods, and ordinary wrappers forwarding callbacks. TaskGroup.start requires explicit specialization when stored as a generic method value; Task.join and TaskGroup.join may be stored directly.

Run `tests/e2e/testdata/accept/synchronized.ms` for complete updates, forwarding, explicit shallow copies, builders, fault cleanup, stale guards, and ancestor reentry. Runtime tests must exercise simultaneous increments, cancellation while waiting and holding, concurrent release, access racing with release/reacquisition, undelivered acquisition disposal, and builder freeze racing with mutation. Reject direct Synchronized get/set, guard construction, and equality/hashing of either synchronized type.

## Data and numeric outcomes

Use the accepted modules in [collection operations](../../../core-language/types/collections.md#lookup-and-updates). In addition:

```manuscript
import panic from "@std/faults.ms"

import Decimal from "@std/decimal.ms"

fn quotient(value: Int, divisor: Int) -> Int:
    return value / divisor

fn remainder(value: Int, divisor: Int) -> Int:
    return value % divisor

test "numeric boundary rules":
    if not (quotient(value: -7, divisor: 2) == -3):
        return panic(message: "check failed")
    if not (remainder(value: -7, divisor: 3) == -1):
        return panic(message: "check failed")
    if not (remainder(value: -9223372036854775808, divisor: -1) == 0):
        return panic(message: "check failed")
    let infinity = 1.0 / 0.0
    let nan = 0.0 / 0.0
    if not ("{infinity}" == "Infinity"):
        return panic(message: "check failed")
    if not (nan != nan):
        return panic(message: "check failed")
    let third = 1d / 3d
    if not ("{third}" == "0.3333333333333333333333333333333333"):
        return panic(message: "check failed")
    let absent: Optional[Int] = none
    if not (1e300.truncate_to_int() == absent):
        return panic(message: "check failed")
    if not ((2.seconds + 1.seconds) == 3.seconds):
        return panic(message: "check failed")
```

Runner-level fault probes use parameters for division by zero, minimum Int/-1, unary minimum Int negation, duration overflow, Decimal overflow, and invalid byte construction. Check normal subnormal/zero Decimal underflow and halfway ties-to-even. Reject out-of-grid Decimal literals and more than 34 significant digits; accept insignificant trailing zeroes. Map mutation tests verify a/b/a-replacement traversal as a→3,b→2, original snapshot retention, and remove/reinsert ordering. Reject source implementations for standard native collection types.

## Entry, adapter, and lifetime integration

Build the complete [CLI main module](../../../standard-library/cli.md) with an ms.toml selecting it, pass two arguments, and expect `Arguments: 2` plus LF and exit 0. Missing/internal/generic/wrong-signature main must fail checking. Inject SIGINT and SIGTERM during joined work and verify joins/cleanup before exits 130/143. A cleanup fault exits 70. Host escalation is separately classified as incomplete cleanup.

Generate a separate schema package for a minimal interface, a native adapter package importing it, and an application importing both; the pinned Go toolchain must build this without an import cycle. Reject interface imports of an application module, invalid/duplicate bindings, absent acquisition disposers, wrong native symbol signatures, and mutable/invalid foreign result values.

Controlled race probes cover acquisition versus cancellation, completion versus stop, admission versus close, repeated close, and close from an admitted job's nested task-group descendant or reporter. The latter must fault before shutdown instead of self-joining. Generic function specialization probes accept regular self/mutual recursion and reject expanding specialization through calls or stored function values before Go emission.

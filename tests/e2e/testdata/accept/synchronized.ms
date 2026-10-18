import {TextError} from "@std/errors.ms"
import {
    expect_contains,
    expect_equal,
    expect_error,
    expect_fault,
    expect_ok,
    expect_some,
    expect_true,
    fail
} from "@std/testing.ms"
import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"
import ListBuilder from "@std/collections.ms"
import ExecutionError from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"
import sleep from "@std/time.ms"

fn identity[T](value: T) T:
    return value

fn execute(operation: fn() Int) Result[Int, ExecutionError]:
    with group = TaskGroup():
        let task = group.start(operation)
        return task.join()

fn increment(locked: SynchronizedGuard[Int]) Unit:
    locked.set(value: locked.get() + 1)

fn release_on_return(counter: Synchronized[Int]) Int:
    with locked = counter.lock():
        increment(locked: locked)
        return locked.get()

fn release_on_error(counter: Synchronized[Int]) Result[Unit, TextError]:
    with locked = counter.lock():
        increment(locked: locked)
        return error(TextError("expected"))

fn read_and_add(value: Int) Int:
    return value + 1

interface Read:
    fn get() Int

type Reader:
    callback: fn() Int

impl Read for Reader:
    fn get() Int:
        return self.callback()

test "shared counter protects complete updates":
    let counter = Synchronized(0)
    let operation = fn():
        for unused in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            with locked = counter.lock():
                increment(locked: locked)

    with group = TaskGroup():
        let first_task = group.start(operation)
        let second_task = group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)

        match group.join():
            ok(_):
                with locked = counter.lock():
                    locked.get() | try expect_equal(expected: 100)
            error(_):
                ((false) | try expect_true)

    release_on_return(counter: counter) | try expect_equal(expected: 101)
    let outcome = release_on_error(counter: counter)
    with locked = counter.lock():
        locked.get() | try expect_equal(expected: 102)

test "function fields collections and interface views share freely":
    var captured = 7
    let callback = fn():
        return captured
    captured = 9
    let callbacks: List[fn() Int] = [identity(value: callback)]

    for stored in callbacks:
        match execute(operation: stored):
            ok(value):
                try expect_equal(value, 7)
            error(_):
                ((false) | try expect_true)

    let readers: List[Read] = [Read(Reader(callback))]

    for reader in readers:
        match execute(operation: reader.get):
            ok(value):
                try expect_equal(value, 7)
            error(_):
                ((false) | try expect_true)

    let make_function = fn():
        return read_and_add

    with group = TaskGroup():
        let first_task = group.start(make_function)

        match group.join():
            ok(_): unit
            error(_):
                ((false) | try expect_true)

        match first_task.join():
            ok(returned):
                try expect_equal(returned(value: 3), 4)
            error(_):
                return fail("task result unavailable")

test "builders can be captured and stored callbacks can map":
    let builder = ListBuilder[Int]()
    let append_item = fn(item: Int):
        builder.append(value: item)
    append_item(item: 1)
    append_item(item: 2)
    append_item(item: 3)
    append_item(item: 4)
    builder.freeze().length() | try expect_equal(expected: 4)

test "error releases guard and preserves committed writes":
    let counter = Synchronized(0)
    let attempt = fn() Result[Unit, Error]:
        with locked = counter.lock():
            locked.set(value: 8)
            return fail("expected")

    with group = TaskGroup():
        let task = group.start(attempt)
        try group.join()
        let result = task.join() | try expect_ok
        let cause = result | try expect_error
        cause.message() | try expect_equal(expected: "expected")

    with locked = counter.lock():
        locked.get() | try expect_equal(expected: 8)

test "guard aliases close once and stale methods fault":
    let counter = Synchronized(0)
    let first = counter.lock()
    let saved_get = first.get
    let alias = Closeable(first)
    alias.close()

    with second = counter.lock():
        first.close()
        second.set(value: 2)

        with group = TaskGroup():
            let first_task = group.start(saved_get)

            match group.join():
                ok(_):
                    ((false) | try expect_true)
                error(_):
                    try expect_equal(second.get(), 2)

test "same-task reentry faults and releases its guard":
    let counter = Synchronized(0)
    let message = try expect_fault(
        fn():
            with locked = counter.lock():
                with again = counter.lock():
                    again.set(3)
    )
    message | try expect_contains(expected: "held by this operation")

    with locked = counter.lock():
        locked.set(3)
        locked.get() | try expect_equal(expected: 3)

test "parent holds lock while a running child waits for it":
    let cell = Synchronized(0)

    with tasks = TaskGroup():
        let child = tasks.start(
            fn() Int:
                sleep(duration: 20.milliseconds)
                with locked = cell.lock():
                    return locked.get()
        )

        with locked = cell.lock():
            sleep(duration: 100.milliseconds)
            locked.set(value: 7)

        match child.join():
            ok(value):
                if value != 7: return fail(message: "got {value}")
            error(_):
                return fail(message: "child failed")

test "ordinary cross-task lock cycle stops at the group timeout":
    let cell = Synchronized(0)

    with locked = cell.lock():
        with tasks = TaskGroup(timeout: 40.milliseconds):
            let child = tasks.start(
                fn() Int:
                    with acquired = cell.lock():
                        return acquired.get()
            )

            let cause = match child.join():
                ok(_):
                    return fail(message: "cycle acquired before release")
                error(cause): cause

            match cause:
                Timeout:
                    locked.set(value: 3)
                _:
                    return fail(message: "unexpected failure {cause}")

    with locked = cell.lock():
        locked.get() | try expect_equal(expected: 3)

test "loop exits release the guard":
    let counter = Synchronized(0)

    for item in [1, 2, 3]:
        with locked = counter.lock():
            locked.set(value: locked.get() + 1)
            if item == 1:
                continue

            break

    with locked = counter.lock():
        locked.get() | try expect_equal(expected: 2)

test "native collection methods preserve ordinary function values":
    let callbacks = [1, 2].map(
        transform: fn(value):
            return fn():
                return value
    )
    let first = fn() Result[Int, Error]:
        let callback = (callbacks.get(0))
        return ok(callback())
    let second = fn() Result[Int, Error]:
        let callback = (callbacks.get(1))
        return ok(callback())

    with group = TaskGroup():
        let first_task = group.start(first)
        let second_task = group.start(second)
        let joined = try group.join()
        (try first_task.join()) | try expect_ok | try expect_equal(expected: 1)
        (try second_task.join()) | try expect_ok | try expect_equal(expected: 2)

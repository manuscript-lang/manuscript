import {Synchronized, SynchronizedGuard} from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"
import ListBuilder from "@std/collections.ms"
import {ExecutionError, TaskGroup} from "@std/tasks.ms"
import panic from "@std/faults.ms"
import sleep from "@std/time.ms"

fn identity[T](value: T) T:
    return value

fn execute(operation: fn() Int) Result[Int, ExecutionError]:
    with group = TaskGroup():
        let task = group.start(operation)
        return task.join()

fn increment(locked: SynchronizedGuard[Int]) Unit:
    locked.set(locked.get() + 1)

fn release_on_return(counter: Synchronized[Int]) Int:
    with locked = counter.lock():
        increment(locked)
        return locked.get()

fn release_on_error(counter: Synchronized[Int]) Result[Unit, String]:
    with locked = counter.lock():
        increment(locked)
        return error("expected")

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
                increment(locked)

    with group = TaskGroup():
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)
        try group.join()
        with locked = counter.lock():
            if not (locked.get() == 100):
                return panic("check failed")

    if not (release_on_return(counter) == 101):
        return panic("check failed")

    let _outcome = release_on_error(counter)
    with locked = counter.lock():
        if not (locked.get() == 102):
            return panic("check failed")

test "function fields collections and interface views share freely":
    var captured = 7
    let callback = fn():
        return captured
    captured = 9
    let callbacks: List[fn() Int] = [identity(callback)]

    for stored in callbacks:
        let value = try execute(stored)
        if not (value == 7):
            return panic("check failed")

    let readers: List[Read] = [Read(Reader(callback))]

    for reader in readers:
        let value = try execute(reader.get)
        if not (value == 7):
            return panic("check failed")

    let make_function = fn():
        return read_and_add

    with group = TaskGroup():
        let first_task = group.start(make_function)
        try group.join()
        let returned = try first_task.join()
        if not (returned(3) == 4):
            return panic("check failed")

test "builders can be captured and stored callbacks can map":
    let builder = ListBuilder[Int]()
    let append_item = fn(item: Int):
        builder.append(item)
    append_item(1)
    append_item(2)
    append_item(3)
    append_item(4)
    if not (builder.freeze().length() == 4):
        return panic("check failed")

test "fault releases guard and preserves committed writes":
    let counter = Synchronized(0)
    let fail = fn():
        with locked = counter.lock():
            locked.set(8)
            panic("expected")

    with group = TaskGroup():
        group.start(fail)
        if group.join().is_ok():
            return panic("check failed")

        with locked = counter.lock():
            if not (locked.get() == 8):
                return panic("check failed")

test "guard aliases close once and stale methods fault":
    let counter = Synchronized(0)
    let first = counter.lock()
    let saved_get = first.get
    let alias = Closeable(first)
    alias.close()

    with second = counter.lock():
        first.close()
        second.set(2)

        with group = TaskGroup():
            group.start(saved_get)
            if group.join().is_ok():
                return panic("check failed")
            if not (second.get() == 2):
                return panic("check failed")

test "same-task reentry faults and releases its guard":
    let counter = Synchronized(0)
    let acquire = fn():
        with locked = counter.lock():
            with again = counter.lock():
                return panic("reentry should fault")

    with group = TaskGroup():
        group.start(acquire)
        if group.join().is_ok():
            return panic("reentry did not fault")

        with locked = counter.lock():
            locked.set(3)

    with locked = counter.lock():
        if locked.get() != 3:
            return panic("fault leaked guard")

test "parent holds lock while a running child waits for it":
    let cell = Synchronized(0)

    with tasks = TaskGroup():
        let child = tasks.start(
            fn() Int:
                sleep(20.milliseconds)
                with locked = cell.lock():
                    return locked.get()
        )

        with locked = cell.lock():
            sleep(100.milliseconds)
            locked.set(7)

        let value = try child.join()
        if value != 7:
            return panic("got {value}")

test "ordinary cross-task lock cycle stops at the group timeout":
    let cell = Synchronized(0)

    with locked = cell.lock():
        with tasks = TaskGroup(40.milliseconds):
            let child = tasks.start(
                fn() Int:
                    with acquired = cell.lock():
                        return acquired.get()
            )
            let joined = child.join()
            if joined.is_ok():
                return panic("cycle acquired before release")

            let cause = joined.unwrap_error()

            match cause:
                Timeout:
                    locked.set(3)
                _:
                    return panic("unexpected failure {cause}")

    with locked = cell.lock():
        if locked.get() != 3:
            return panic("timeout lost committed data")

test "loop exits release the guard":
    let counter = Synchronized(0)

    for item in [1, 2, 3]:
        with locked = counter.lock():
            locked.set(locked.get() + 1)
            if item == 1:
                continue

            break

    with locked = counter.lock():
        if not (locked.get() == 2):
            return panic("check failed")

test "native collection methods preserve ordinary function values":
    let callbacks = [1, 2].map(
        fn(value):
            return fn():
                return value
    )
    let first = fn():
        if let callback = callbacks.at(0):
            return callback()

        return panic("missing callback")
    let second = fn():
        if let callback = callbacks.at(1):
            return callback()

        return panic("missing callback")

    with group = TaskGroup():
        let first_task = group.start(first)
        let second_task = group.start(second)
        try group.join()
        let first_value = try first_task.join()
        let second_value = try second_task.join()
        if first_value != 1 or second_value != 2:
            return panic("check failed")

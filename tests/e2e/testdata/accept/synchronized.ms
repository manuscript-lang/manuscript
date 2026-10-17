import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"
import ListBuilder from "@std/collections.ms"
import ExecutionError from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"
import sleep from "@std/time.ms"

fn identity[T](value: T) -> T:
    return value

fn execute(operation: fn() -> Int) -> Result[Int, ExecutionError]:
    with group = TaskGroup():
        let task = group.start(operation)
        return task.join()

fn increment(locked: SynchronizedGuard[Int]) -> Unit:
    locked.set(value: locked.get() + 1)

fn release_on_return(counter: Synchronized[Int]) -> Int:
    with locked = counter.lock():
        increment(locked: locked)
        return locked.get()

fn release_on_error(counter: Synchronized[Int]) -> Result[Unit, String]:
    with locked = counter.lock():
        increment(locked: locked)
        return error("expected")

fn read_and_add(value: Int) -> Int:
    return value + 1

interface Read:
    fn get() -> Int

type Reader:
    callback: fn() -> Int

impl Read for Reader:
    fn get() -> Int:
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
        try group.join()
        with locked = counter.lock():
            if not (locked.get() == 100):
                return panic(message: "check failed")

    if not (release_on_return(counter: counter) == 101):
        return panic(message: "check failed")

    let outcome = release_on_error(counter: counter)
    with locked = counter.lock():
        if not (locked.get() == 102):
            return panic(message: "check failed")

test "function fields collections and interface views share freely":
    var captured = 7
    let callback = fn():
        return captured
    captured = 9
    let callbacks: List[fn() -> Int] = [identity(value: callback)]
    for stored in callbacks:
        if not (execute(operation: stored).unwrap_or(0) == 7):
            return panic(message: "check failed")
    let readers: List[Read] = [Read(Reader(callback))]
    for reader in readers:
        if not (execute(operation: reader.get).unwrap_or(0) == 7):
            return panic(message: "check failed")
    let make_function = fn():
        return read_and_add

    with group = TaskGroup():
        let first_task = group.start(make_function)
        try group.join()
        let returned = try first_task.join()
        if not (returned(value: 3) == 4):
            return panic(message: "check failed")

test "builders can be captured and stored callbacks can map":
    let builder = ListBuilder[Int]()
    let append_item = fn(item: Int):
        builder.append(value: item)
    append_item(item: 1)
    append_item(item: 2)
    append_item(item: 3)
    append_item(item: 4)
    if not (builder.freeze().length() == 4):
        return panic(message: "check failed")

test "fault releases guard and preserves committed writes":
    let counter = Synchronized(0)
    let fail = fn():
        with locked = counter.lock():
            locked.set(value: 8)
            panic(message: "expected")

    with group = TaskGroup():
        let first_task = group.start(fail)
        if group.join().is_ok():
            return panic(message: "check failed")

        with locked = counter.lock():
            if not (locked.get() == 8):
                return panic(message: "check failed")

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
            if group.join().is_ok():
                return panic(message: "check failed")
            if not (second.get() == 2):
                return panic(message: "check failed")

test "same-task reentry faults and releases its guard":
    let counter = Synchronized(0)
    let acquire = fn():
        with locked = counter.lock():
            with again = counter.lock():
                return panic(message: "reentry should fault")

    with group = TaskGroup():
        let first_task = group.start(acquire)
        if group.join().is_ok():
            return panic(message: "reentry did not fault")

        with locked = counter.lock():
            locked.set(value: 3)

    with locked = counter.lock():
        if locked.get() != 3:
            return panic(message: "fault leaked guard")

test "parent holds lock while a running child waits for it":
    let cell = Synchronized(0)

    with tasks = TaskGroup():
        let child = tasks.start(
            fn() -> Int:
                sleep(duration: 20.milliseconds)
                with locked = cell.lock():
                    return locked.get()
        )

        with locked = cell.lock():
            sleep(duration: 100.milliseconds)
            locked.set(value: 7)

        let value = try child.join()
        if value != 7:
            return panic(message: "got {value}")

test "ordinary cross-task lock cycle stops at the group timeout":
    let cell = Synchronized(0)

    with locked = cell.lock():
        with tasks = TaskGroup(timeout: 40.milliseconds):
            let child = tasks.start(
                fn() -> Int:
                    with acquired = cell.lock():
                        return acquired.get()
            )
            let joined = child.join()
            if joined.is_ok():
                return panic(message: "cycle acquired before release")

            let cause = joined.unwrap_error()

            match cause:
                Timeout:
                    locked.set(value: 3)
                _:
                    return panic(message: "unexpected failure {cause}")

    with locked = cell.lock():
        if locked.get() != 3:
            return panic(message: "timeout lost committed data")

test "loop exits release the guard":
    let counter = Synchronized(0)

    for item in [1, 2, 3]:
        with locked = counter.lock():
            locked.set(value: locked.get() + 1)
            if item == 1:
                continue

            break

    with locked = counter.lock():
        if not (locked.get() == 2):
            return panic(message: "check failed")

test "native collection methods preserve ordinary function values":
    let callbacks = [1, 2].map(
        transform: fn(value):
            return fn():
                return value
    )
    let first = fn():
        match callbacks.at(index: 0):
            some(callback):
                return callback()
            none:
                return panic(message: "missing callback")
    let second = fn():
        match callbacks.at(index: 1):
            some(callback):
                return callback()
            none:
                return panic(message: "missing callback")

    with group = TaskGroup():
        let first_task = group.start(first)
        let second_task = group.start(second)
        try group.join()
        let first_value = try first_task.join()
        let second_value = try second_task.join()
        if first_value != 1 or second_value != 2:
            return panic(message: "check failed")

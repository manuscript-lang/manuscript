import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"
import List from "@std/collections.ms"
import ListBuilder from "@std/collections.ms"
import Result from "@std/result.ms"
import ExecutionError from "@std/tasks.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

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
        for unused in [
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10
        ]:
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
                    if not (locked.get() == 100):
                        return panic(message: "check failed")

            error(_):
                if not (false):
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
        match execute(operation: stored):
            ok(value):
                if not (value == 7):
                    return panic(message: "check failed")

            error(_):
                if not (false):
                    return panic(message: "check failed")

    let readers: List[Read] = [Read(Reader(callback))]

    for reader in readers:
        match execute(operation: reader.get):
            ok(value):
                if not (value == 7):
                    return panic(message: "check failed")

            error(_):
                if not (false):
                    return panic(message: "check failed")

    let make_function = fn():
        return read_and_add

    with group = TaskGroup():
        let first_task = group.start(make_function)

        match group.join():
            ok(_): unit
            error(_):
                if not (false):
                    return panic(message: "check failed")

        match first_task.join():
            ok(returned):
                if not (returned(value: 3) == 4):
                    return panic(message: "check failed")

            error(_):
                return panic("task result unavailable")

test "builders can be captured and stored callbacks can map":
    let builder = ListBuilder[Int]()
    let append_item = fn(item: Int):
        builder.append(value: item)
    let task1 = fn():
        append_item(item: 1)
    let task2 = fn():
        append_item(item: 2)
    let task3 = fn():
        append_item(item: 3)
    let task4 = fn():
        append_item(item: 4)

    with group = TaskGroup():
        let first_task = group.start(task1)
        let second_task = group.start(task2)
        group.start(task3)
        group.start(task4)

        match group.join():
            ok(_):
                if not (builder.freeze().length() == 4):
                    return panic(message: "check failed")

            error(_):
                if not (false):
                    return panic(message: "check failed")

test "fault releases guard and preserves committed writes":
    let counter = Synchronized(0)
    let fail = fn():
        with locked = counter.lock():
            locked.set(value: 8)
            panic(message: "expected")

    with group = TaskGroup():
        let first_task = group.start(fail)

        match group.join():
            ok(_):
                if not (false):
                    return panic(message: "check failed")

            error(_):
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

            match group.join():
                ok(_):
                    if not (false):
                        return panic(message: "check failed")

                error(_):
                    if not (second.get() == 2):
                        return panic(message: "check failed")

test "ancestor reentry faults without hanging":
    let counter = Synchronized(0)

    with locked = counter.lock():
        let acquire = fn():
            with again = counter.lock():
                if not (false):
                    return panic(message: "check failed")

        with group = TaskGroup():
            let first_task = group.start(acquire)

            match group.join():
                ok(_):
                    if not (false):
                        return panic(message: "check failed")

                error(_):
                    locked.set(value: 3)

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

        match group.join():
            ok(_): unit
            error(_):
                return panic(message: "task callbacks failed")

        let first_value = match first_task.join():
            ok(first_value): first_value
            error(_):
                return panic("task result unavailable")

        match second_task.join():
            ok(second_value):
                if first_value != 1 or second_value != 2:
                    return panic(message: "check failed")

            error(_):
                return panic("task result unavailable")

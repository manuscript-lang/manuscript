import Synchronized from "@std/sync.ms"
import SynchronizedGuard from "@std/sync.ms"
import Closeable from "@std/cleanup.ms"
import List from "@std/collections.ms"
import ListBuilder from "@std/builders.ms"
import Result from "@std/result.ms"
import ExecutionError from "@std/tasks.ms"
import parallel from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn identity[T](value: T) -> T:
    return value

fn execute(operation: fn() -> Int) -> Result[Int, ExecutionError]:
    let [value] = try parallel(tasks: [operation])
    return ok(value: value)

fn increment(locked: SynchronizedGuard[Int]) -> Unit:
    locked.set(value: locked.get() + 1)

fn release_on_return(counter: Synchronized[Int]) -> Int:
    with locked = counter.lock():
        increment(locked: locked)
        return locked.get()

fn release_on_error(counter: Synchronized[Int]) -> Result[Unit, String]:
    with locked = counter.lock():
        increment(locked: locked)
        return error(cause: "expected")

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
    let counter = Synchronized(value: 0)
    let operation = fn() -> Unit:
        for unused in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            with locked = counter.lock():
                increment(locked: locked)
    match parallel(tasks: [operation, operation, operation, operation, operation, operation, operation, operation, operation, operation]):
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
    let callback = fn() -> Int:
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
    let readers: List[Read] = [Read(value: Reader(callback: callback))]
    for reader in readers:
        match execute(operation: reader.get):
            ok(value):
                if not (value == 7):
                    return panic(message: "check failed")
            error(_):
                if not (false):
                    return panic(message: "check failed")
    let make_function = fn() -> fn(value: Int) -> Int:
        return read_and_add
    match parallel(tasks: [make_function]):
        ok(values):
            let [returned] = values
            if not (returned(value: 3) == 4):
                return panic(message: "check failed")
        error(_):
            if not (false):
                return panic(message: "check failed")

test "builders can be captured and stored callbacks can map":
    let builder = ListBuilder[Int]()
    let append_item = fn(item: Int) -> Unit:
        builder.append(value: item)
    let task1 = fn() -> Unit:
        append_item(item: 1)
    let task2 = fn() -> Unit:
        append_item(item: 2)
    let task3 = fn() -> Unit:
        append_item(item: 3)
    let task4 = fn() -> Unit:
        append_item(item: 4)
    match parallel(tasks: [task1, task2, task3, task4]):
        ok(_):
            if not (builder.freeze().length() == 4):
                return panic(message: "check failed")
        error(_):
            if not (false):
                return panic(message: "check failed")

test "fault releases guard and preserves committed writes":
    let counter = Synchronized(value: 0)
    let fail = fn() -> Unit:
        with locked = counter.lock():
            locked.set(value: 8)
            panic(message: "expected")
    match parallel(tasks: [fail]):
        ok(_):
            if not (false):
                return panic(message: "check failed")
        error(_):
            with locked = counter.lock():
                if not (locked.get() == 8):
                    return panic(message: "check failed")

test "guard aliases close once and stale methods fault":
    let counter = Synchronized(value: 0)
    let first = counter.lock()
    let saved_get = first.get
    let alias = Closeable(value: first)
    alias.close()
    with second = counter.lock():
        first.close()
        second.set(value: 2)
        match parallel(tasks: [saved_get]):
            ok(_):
                if not (false):
                    return panic(message: "check failed")
            error(_):
                if not (second.get() == 2):
                    return panic(message: "check failed")

test "ancestor reentry faults without hanging":
    let counter = Synchronized(value: 0)
    with locked = counter.lock():
        let acquire = fn() -> Unit:
            with again = counter.lock():
                if not (false):
                    return panic(message: "check failed")
        match parallel(tasks: [acquire]):
            ok(_):
                if not (false):
                    return panic(message: "check failed")
            error(_):
                locked.set(value: 3)

test "loop exits release the guard":
    let counter = Synchronized(value: 0)
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
    let callbacks = [1, 2].map(transform: fn(value: Int) -> fn() -> Int:
        return fn() -> Int:
            return value
    )
    let first = fn() -> Int:
        match callbacks.get(index: 0):
            some(callback):
                return callback()
            none:
                return panic(message: "missing callback")
    let second = fn() -> Int:
        match callbacks.get(index: 1):
            some(callback):
                return callback()
            none:
                return panic(message: "missing callback")
    match parallel(tasks: [first, second]):
        ok(outcomes):
            let [first_value, second_value] = outcomes
            if first_value != 1 or second_value != 2:
                return panic(message: "check failed")
        error(_):
            return panic(message: "parallel callbacks failed")

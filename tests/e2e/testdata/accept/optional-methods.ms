import Optional from "@std/optional.ms"
import panic from "@std/faults.ms"
import JsonLimits from "@std/json.ms"
import List from "@std/collections.ms"

type Counter:
    calls: Int

fn fallback(counter: Counter) -> Int:
    counter.calls = counter.calls + 1
    return 42

fn value_or[T](value: Optional[T], fallback: T) -> T:
    return value.unwrap_or(fallback)

fn increment(value: Int) -> Int: return value + 1

test "Optional presence and extraction preserve false and zero":
    let present: Optional[Int] = some(value: 0)
    let missing: Optional[Int] = none
    if not (present.is_some()): return panic("zero was absent")
    if present.is_none(): return panic("some reported none")
    if missing.is_some(): return panic("none reported some")
    if not (missing.is_none()): return panic("none was present")
    if present.unwrap() != 0: return panic("payload lost")
    let flag: Optional[Bool] = some(value: false)
    if flag.unwrap(): return panic("false payload lost")
    if value_or(value: missing, fallback: 7) != 7: return panic("generic fallback")
    if value_or(value: present, fallback: 7) != 0: return panic("generic payload")
    if missing.is_some():
        return panic(missing.unwrap().toString())

test "Optional fallbacks distinguish eager and lazy evaluation":
    let present: Optional[Int] = some(value: 0)
    let missing: Optional[Int] = none
    let counter = Counter(calls: 0)
    if present.unwrap_or(fallback(counter)) != 0: return panic("eager fallback result")
    if counter.calls != 1: return panic("fallback expression was not evaluated")
    let create = fn() -> Int: return fallback(counter)
    if present.unwrap_or_else(create) != 0: return panic("lazy payload")
    if counter.calls != 1: return panic("some invoked fallback")
    if missing.unwrap_or_else(create) != 42: return panic("lazy fallback")
    if counter.calls != 2: return panic("none must invoke fallback once")

test "Optional methods retain generic payload and receiver identity":
    let inner: Optional[Int] = none
    let outer: Optional[Optional[Int]] = some(value: inner)
    if not (outer.is_some()): return panic("nested optional flattened")
    if not (outer.unwrap().is_none()): return panic("nested none lost")
    let counter = Counter(calls: 0)
    let record: Optional[Counter] = some(value: counter)
    record.unwrap().calls = 3
    if counter.calls != 3: return panic("unwrap copied the payload")
    let extract = record.unwrap
    extract().calls = 4
    if counter.calls != 4: return panic("stored method lost its receiver")
    let callback: Optional[fn(value: Int) -> Int] = some(value: increment)
    if callback.unwrap()(2) != 3: return panic("function payload type lost")
    let snapshot = outer.clone()
    if snapshot != outer: return panic("optional value semantics changed")

test "Optional fallbacks preserve standard option records":
    let limits = JsonLimits(max_bytes: some(value: -1))
    let missing: Optional[JsonLimits] = none
    let extracted = missing.unwrap_or(limits)
    if extracted.max_bytes.unwrap() != -1: return panic("generic record normalized")
    if not (extracted.max_depth.is_none()): return panic("generic record default changed")
    extracted.max_values = some(value: 7)
    if limits.max_values.unwrap() != 7: return panic("generic fallback cloned the record")

test "Optional methods work on inferred library return values":
    let values = [1, 2]
    if values.at(0).unwrap() != 1: return panic("inferred payload")
    if values.at(5).unwrap_or(9) != 9: return panic("inferred fallback")

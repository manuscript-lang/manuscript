# conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/inference-call-order.ms
import {expect_equal} from "@std/testing.ms"

fn identity[T](value: T) T: value

fn first[T](left: T, right: T) T: left

fn optional[T](value: Optional[T], fallback: T) ref T: value.get(fallback)

fn describe[T](value: T, cause: Error) ref String: cause.message()

type Events:
    values: List[Int]

type Failure:
    detail: String

impl Error for Failure:
    fn message() ref String: self.detail

type GenericFailure[T]:
    detail: T

impl Error for GenericFailure[T]:
    fn message() String: self.detail.to_string()

fn record(var events: Events, value: Int) Int:
    events.values.append(value)
    return value

test "reused inference preserves evaluation and argument conversions":
    var events = Events([])
    let selected = first(
        right: identity(identity(record(var events, value: 2))),
        left: identity(identity(record(var events, value: 1)))
    )
    try expect_equal(selected, 1)
    try expect_equal(events.values, [2, 1])

    let wrapped = optional(value: identity(record(var events, value: 3)), fallback: 0)
    try expect_equal(wrapped, 3)
    try expect_equal(events.values, [2, 1, 3])

    let message = describe(value: 1, cause: identity(Failure("cached")))
    try expect_equal(message, "cached")

    let generic_message = describe(value: 1, cause: identity(GenericFailure(4)))
    try expect_equal(generic_message, "4")

    let offset = 7
    let callback = identity(identity(fn(value: Int): offset + value))
    try expect_equal(callback(3), 10)

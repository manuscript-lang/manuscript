# conform: tags=records,interfaces,mutation,stdlib-shared,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import Shared from "@std/concurrency/shared.ms"
import expect_equal, expect_fault from "@std/test/test.ms"

type Config:
    name: String
    tags: List[String]

interface Speaker:
    fn say() String

type Dog:
    name: String

impl Speaker for Dog:
    fn say() String:
        return self.name + " says woof"

type Holder:
    config: Shared[Config]
    speaker: Shared[Speaker]

fn make(name: String) Holder:
    let config = Shared(
        Config(name.clone(), ["a-tag-long-enough-for-the-heap", "second"])
    )
    let speaker: Shared[Speaker] = Shared(Dog(name))
    return Holder(config, speaker)

fn child(var holder: Holder) Holder:
    return Holder(holder.config, holder.speaker)

test "copies of a shared value read the same payload":
    var first = make("a-name-long-enough-for-the-heap")
    var second = child(var first)
    let third = child(var second)
    try expect_equal(third.config.name, "a-name-long-enough-for-the-heap")
    try expect_equal(first.config.tags[0], "a-tag-long-enough-for-the-heap")
    try expect_equal(third.speaker.say(), "a-name-long-enough-for-the-heap says woof")

test "the payload outlives the original holder":
    var made = make("x-name-long-enough-for-the-heap-too")
    let kept = child(var made)
    try expect_equal(kept.config.tags.length(), 2)

type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    var fn bump_then(after: fn() Unit) Unit:
        self.values.append(1)
        after()

    fn count_after(after: fn() Unit) Int:
        after()
        return self.values.length()

fn bump(var shared: Shared[Counter]) Unit:
    shared.bump()

test "a var handle changes the payload every holder sees":
    var first = Shared(Counter([]))
    var second = first
    bump(var first)
    bump(var second)
    try expect_equal(first.values.length(), 2)

test "a read inside a change of the same payload sees the value":
    var shared = Shared(Counter([]))
    let view = shared
    var seen = 0
    shared.bump_then(fn() Unit: seen = view.values.length())
    try expect_equal(seen, 1)
    try expect_equal(view.values.length(), 1)

test "a read inside a read call on the same payload sees the value":
    var shared = Shared(Counter([4, 5]))
    let view = shared
    var seen = 0
    let count = shared.count_after(fn() Unit: seen = view.values.length())
    try expect_equal(count, 2)
    try expect_equal(seen, 2)

type Hook:
    run: fn() Unit

# A callback the checker cannot see (stored in a record) that changes the value the call is
# using faults rather than changing it under the call.
test "a hidden change inside a call on the same payload faults":
    var shared = Shared(Counter([]))
    var other = shared
    let hook = Hook(fn() Unit: other.bump())
    let message = try expect_fault(
        fn() Unit:
            shared.bump_then(hook.run)
    )
    try expect_equal(
        message,
        "a Shared value was used again inside a call on it from the same task; finish the call first, or change the value inside that call"
    )

fn append_seven(var items: List[Int]) Unit:
    items.append(7)

fn drop_after_call() Unit:
    var shared: Shared[List[Int]] = Shared([])
    append_seven(var shared)
    if shared.length() != 1:
        return

    let _held = [shared]

test "a box dropped after a call does not free the payload twice":
    drop_after_call()

    var first = [1, 2, 3, 4]
    let second = [5, 6, 7, 8]
    first.append(9)
    first[0] = 0
    try expect_equal(first, [0, 2, 3, 4, 9])
    try expect_equal(second, [5, 6, 7, 8])

test "an optional payload keeps its value when replaced":
    let five: Int? = 5
    var shared: Shared[Int?] = Shared(five)
    let read: Int? = shared
    try expect_equal(read, 5)
    shared = read

    let again: Int? = shared
    try expect_equal(again, 5)

type Pair:
    flag: Bool
    value: Int?

test "a record payload with an optional field after a flag survives replacement":
    var shared = Shared(Pair(flag: 1 == 1, value: 5))
    shared = Pair(flag: 1 == 2, value: shared.value)
    try expect_equal(shared.value, 5)
    try expect_equal(shared.flag, 1 == 2)

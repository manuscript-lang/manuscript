# conform: tags=records,interfaces,mutation,stdlib-shared,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/shared.ms" import share, Shared
from "@std/testing.ms" import expect_equal, expect_fault

type Config:
    name: String
    tags: List[String]

interface Speaker:
    def say() -> String

type Dog:
    name: String

impl Speaker for Dog:
    def say() -> String:
        return self.name + " says woof"

type Holder:
    config: Shared[Config]
    speaker: Shared[Speaker]

def make(name: String) -> Holder:
    let config = share(
        Config(name.clone(), ["a-tag-long-enough-for-the-heap", "second"])
    )
    let speaker = share[Speaker](Dog(name))
    return Holder(config, speaker)

def child(holder: Holder) -> Holder:
    return Holder(holder.config, holder.speaker)

test "copies of a shared value read the same payload":
    let first = make("a-name-long-enough-for-the-heap")
    let second = child(first)
    let third = child(second)
    try expect_equal(third.config.get().name, "a-name-long-enough-for-the-heap")
    try expect_equal(first.config.get().tags[0], "a-tag-long-enough-for-the-heap")
    try expect_equal(
        third.speaker.get().say(), "a-name-long-enough-for-the-heap says woof"
    )

test "the payload outlives the original holder":
    let kept = child(make("x-name-long-enough-for-the-heap-too"))
    try expect_equal(kept.config.get().tags.length(), 2)

type Counter:
    values: List[Int]

impl Counter:
    var def bump() -> Unit:
        self.values.append(1)

def bump(shared: Shared[Counter]) -> Unit:
    var counter = shared.take()
    counter.bump()
    shared.put(counter)

test "take and put change the payload every holder sees":
    let first = share(Counter([]))
    let second = first
    bump(first)
    bump(second)
    try expect_equal(first.get().values.length(), 2)

test "a second take while the payload is out faults":
    let shared = share(Counter([]))
    let held = shared.take()

    let message = try expect_fault(
        lambda () -> Unit:
            let second = shared.take()
            shared.put(second)
    )

    try expect_equal(message, "shared value is in use")
    shared.put(held)

def append_seven(shared: Shared[List[Int]]) -> Unit:
    var items = shared.take()
    items.append(7)
    shared.put(items)

def drop_while_taken() -> Unit:
    let shared: Shared[List[Int]] = share([])
    append_seven(shared)
    let taken = shared.take()
    if taken.length() != 1:
        return

test "a box dropped while its payload is out does not free the payload twice":
    drop_while_taken()
    var first = [1, 2, 3, 4]
    let second = [5, 6, 7, 8]
    first.append(9)
    first[0] = 0
    try expect_equal(first, [0, 2, 3, 4, 9])
    try expect_equal(second, [5, 6, 7, 8])

test "an optional payload keeps its value through take and put":
    let shared: Shared[Optional[Int]] = share(some(5))
    try expect_equal(shared.get(), some(5))
    let taken = shared.take()
    shared.put(taken)
    try expect_equal(shared.get(), some(5))

type Pair:
    flag: Bool
    value: Optional[Int]

test "a record payload with an optional field after a flag survives take and put":
    let shared = share(Pair(flag: 1 == 1, value: some(5)))
    var pair = shared.take()
    pair = Pair(flag: 1 == 2, value: pair.value)
    shared.put(pair)
    try expect_equal(shared.get().value, some(5))
    try expect_equal(shared.get().flag, 1 == 2)

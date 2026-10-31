# conform: tags=records,interfaces,mutation,stdlib-shared,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import share, Shared from "@std/shared.ms"
import lock from "@std/sync.ms"
import expect_equal, expect_fault from "@std/test.ms"

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
    let config = share(
        Config(name.clone(), ["a-tag-long-enough-for-the-heap", "second"])
    )
    let speaker = share[Speaker](Dog(name))
    return Holder(config, speaker)

fn child(holder: Holder) Holder:
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
    var fn bump() Unit:
        self.values.append(1)

fn bump(shared: Shared[Counter]) Unit:
    var guard = lock(shared)
    guard.value.bump()

test "lock changes the payload every holder sees":
    let first = share(Counter([]))
    let second = first
    bump(first)
    bump(second)
    try expect_equal(first.get().values.length(), 2)

test "a read while the payload is locked faults":
    let shared = share(Counter([]))
    var held = lock(shared)
    let message = try expect_fault(
        fn() Unit:
            let _length = shared.get().values.length()
    )
    try expect_equal(message, "shared value is in use")
    held.value.bump()
    held.close()
    try expect_equal(shared.get().values.length(), 1)

fn append_seven(shared: Shared[List[Int]]) Unit:
    var items = lock(shared)
    items.value.append(7)

fn drop_while_locked() Unit:
    let shared: Shared[List[Int]] = share([])
    append_seven(shared)

    let guard = lock(shared)
    if guard.value.length() != 1:
        return

    let _held = [guard]

test "a box dropped while its payload is locked does not free the payload twice":
    drop_while_locked()

    var first = [1, 2, 3, 4]
    let second = [5, 6, 7, 8]
    first.append(9)
    first[0] = 0
    try expect_equal(first, [0, 2, 3, 4, 9])
    try expect_equal(second, [5, 6, 7, 8])

test "an optional payload keeps its value through lock":
    let five: Int? = 5
    let shared: Shared[Int?] = share(five)
    try expect_equal(shared.get(), 5)

    var held = lock(shared)
    held.value = held.value
    held.close()
    try expect_equal(shared.get(), 5)

type Pair:
    flag: Bool
    value: Int?

test "a record payload with an optional field after a flag survives lock":
    let shared = share(Pair(flag: 1 == 1, value: 5))
    var pair = lock(shared)
    pair.value = Pair(flag: 1 == 2, value: pair.value.value)
    pair.close()
    try expect_equal(shared.get().value, 5)
    try expect_equal(shared.get().flag, 1 == 2)

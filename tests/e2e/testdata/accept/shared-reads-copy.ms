import Shared from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

# A `Shared[T]` handle is `Copy`: another copy of it can replace the value while a reader
# holds what it read, so a kept read is a copy, never a view of the box.
type State:
    case Idle
    case Running(name: String)

test "a loop over a shared value walks a copy":
    var sh = Shared(["ada lovelace", "grace hopper", "barbara liskov"])
    var other = sh
    var seen: List[String] = []

    for name in sh:
        seen.append(name.clone())
        other = ["replaced one", "replaced two", "replaced three"]

    try expect_equal(seen, ["ada lovelace", "grace hopper", "barbara liskov"])

test "a let of a shared value keeps a copy":
    var sh = Shared(["ada lovelace", "grace hopper"])
    var other = sh
    let names: List[String] = sh
    other = ["replaced"]
    try expect_equal(names[1], "grace hopper")

test "a field read through a handle keeps a copy":
    var sh = Shared(["ada lovelace", "grace hopper"])
    var other = sh
    let first = sh[0]
    other[0] = "replaced"
    try expect_equal(first, "ada lovelace")

test "a match payload of a shared value is a copy":
    var sh = Shared(State.Running("ada lovelace"))
    var other = sh

    match sh:
        Running(n):
            other = State.Running("replaced")
            try expect_equal(n, "ada lovelace")
        Idle: try expect_equal(1, 0)

test "if let on a shared optional keeps a copy":
    var maybe: Shared[String?] = Shared("present and long enough for the heap")
    var other = maybe

    if let text = maybe:
        other = none
        try expect_equal(text, "present and long enough for the heap")

    let gone: String? = maybe
    try expect_equal(gone, none)

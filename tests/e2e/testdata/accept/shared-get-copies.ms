import share, lock from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

# A `Shared[T]` handle is `Copy`: another copy of it can replace the value while a reader
# holds what `get()` returned, so a kept result is a copy, never a view of the cell.
type State:
    case Idle
    case Running(name: String)

test "a loop over a shared value walks a copy":
    let sh = share(["ada lovelace", "grace hopper", "barbara liskov"])
    let other = sh
    var seen: List[String] = []

    for name in sh.get():
        seen.append(name.clone())

        var g = lock(other)
        g.value = ["replaced one", "replaced two", "replaced three"]

    try expect_equal(seen, ["ada lovelace", "grace hopper", "barbara liskov"])

test "a let of a shared value keeps a copy":
    let sh = share(["ada lovelace", "grace hopper"])
    let other = sh
    let names = sh.get()
    var g = lock(other)
    g.value = ["replaced"]
    try g.close()
    try expect_equal(names[1], "grace hopper")

test "a match payload of a shared value is a copy":
    let sh = share(State.Running("ada lovelace"))
    let other = sh

    match sh.get():
        Running(n):
            var g = lock(other)
            g.value = State.Running("replaced")
            try g.close()
            try expect_equal(n, "ada lovelace")
        Idle: try expect_equal(1, 0)

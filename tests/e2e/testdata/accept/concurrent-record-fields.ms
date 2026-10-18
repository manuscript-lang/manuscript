import TaskGroup from "@std/tasks.ms"
import expect_equal from "@std/testing.ms"

type Counter:
    hits: Int
    last: String

# Unsynchronized field writes from tasks may lose updates, but they must not
# crash the process with Go's "concurrent map writes".
test "concurrent record field writes do not crash":
    let counter = Counter(hits: 0, last: "")

    with tasks = TaskGroup():
        var t = 0

        while t < 8:
            let id = t
            tasks.start(
                fn() Int:
                    var i = 0

                    while i < 2000:
                        counter.hits = counter.hits + 1
                        counter.last = "t{id}"
                        i = i + 1

                    return id
            )
            t = t + 1

        tasks.join()

    counter.last.length() | try expect_equal(expected: 2)

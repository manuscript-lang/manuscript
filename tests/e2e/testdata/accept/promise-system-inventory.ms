import expect_equal from "@std/test/test.ms"
import promise, wait_all from "@std/concurrency/promise.ms"
import cpus, network_interfaces from "@std/os/process.ms"

fn counts() Int!:
    let c = try cpus()
    let n = try network_interfaces()
    return ok(c.length() + n.length())

test "system inventories work from promises on any thread":
    let here = counts().get(-1)
    let all = wait_all(
        [promise(fn: counts()), promise(fn: counts()), promise(fn: counts())]
    )
    for n in all.get([]):
        try expect_equal(n, here)

// A native network handle holds non-atomic state, so using it from the thread of another promise is a
// named fault rather than a data race (#3047). The main thread stays busy so an idle thread takes the promise.
import expect_ok, expect_error, expect_contains, expect_true from "@std/test/test.ms"
import with_resolver, Network from "@std/net/net.ms"
import promise from "@std/concurrency/promise.ms"

fn open_one(net: Network) String!:
    let l = try net.listen("127.0.0.1:0")
    return ok(l.address())

test "a network used in a promise on another thread faults with the cause":
    let net = with_resolver("127.0.0.1:53") | try expect_ok
    let p = promise(fn: open_one(net))
    var n = 0
    for i in 0..1500000000:
        n = n + i % 7

    let cause = p.wait() | try expect_error
    let _ = try expect_true(n > 0)
    return expect_contains(cause.message, "different thread")

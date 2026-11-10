// A native handle built on `Rc` and `RefCell` holds non-atomic state, so using it from the thread of another
// promise is a named fault rather than a data race (#3047). The main thread stays busy so an idle thread takes
// the promise. A `Network` is shared between threads on purpose (see `net.ms`, "resolve returns typed DNS records").
import expect_error, expect_contains, expect_true, expect_ok from "@std/test/test.ms"
import with_resolver, Network from "@std/net/net.ms"
import headers, HttpHeaders from "@std/net/http.ms"
import promise from "@std/concurrency/promise.ms"

fn open_one(net: Network) String!:
    l := try net.listen("127.0.0.1:0")
    return ok(l.address())

fn names_of(h: HttpHeaders) List[String]!:
    return ok(h.names())

test "http headers used in a promise on another thread fault with the cause":
    h := headers()
    p := promise(fn: names_of(h))
    var n = 0
    for i in 0..1500000000:
        n += i % 7

    cause := p.wait() | try expect_error
    _ := try expect_true(n > 0)
    return expect_contains(cause.message, "different thread")

test "a network used in a promise on another thread keeps working":
    net := with_resolver("127.0.0.1:53") | try expect_ok
    p := promise(fn: open_one(net))
    var n = 0
    for i in 0..1500000000:
        n += i % 7

    address := p.wait() | try expect_ok
    _ := try expect_true(n > 0)
    return expect_contains(address, "127.0.0.1:")

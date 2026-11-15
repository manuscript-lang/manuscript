import Promise, promise from "@std/concurrency/promise.ms"
import Bytes from "@std/bytes.ms"
import Connection from "@std/net/net.ms"

fn touch(c: Connection) Int!:
    return ok(1)

fn hold(var c: Connection) Promise[Int]:
    return promise(fn: touch(c))  // error: captures the `var` parameter `c`

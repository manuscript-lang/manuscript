import Promise, promise from "@std/concurrency/promise.ms"

fn length_of(address: String) Int!:
    return ok(address.length())

fn start(address: String) Promise[Int]:
    return promise(fn: length_of(address))

fn demo() Int:
    address := "localhost"
    p := start(address)  // error: `address` is moved here but used again
    return address.length() + p.wait().get(0)

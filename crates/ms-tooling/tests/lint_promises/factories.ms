import promise, Promise from "@std/concurrency/promise.ms"

fn make(value: Int) Promise[Int]:
    return promise(fn: ok(value))

type Factory:
    make: fn(Int) Promise[Int]

fn main() Unit:
    let _factory = Factory(make: make)
    EXPRESSION

// expect-stdout: close 1
// expect-stdout: ordinary 2
// expect-stdout: close 2
// expect-stdout: default 34
// expect-stdout: close 3
// expect-stdout: generic 6
// expect-stdout: borrowed 8
// expect-stdout: close 4
// expect-stdout: after borrowed
// expect-stdout: shared 13
// expect-stdout: close 7
// expect-stdout: after shared
import Closeable, print from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!:
        print("close {self.id}")
        return ok(unit)

impl Marker:
    fn status() Int: self.id

    fn with_default(offset: Int = 10) Int: self.id + offset

    fn generic[T](_tag: T) Int: self.id

    var fn bump(delta: Int = 1) Int:
        self.id += delta
        return self.id

fn marker(id: Int) Marker: Marker(id)

fn ordinary() Int:
    let read = marker(1).status
    let first = read()
    return first + read()

fn defaulted() Int:
    let read = marker(2).with_default
    let first = read()
    return first + read(20)

fn generic() Int:
    let read = marker(3).generic[Int]
    let first = read(10)
    return first + read(20)

fn borrow(value: Marker) Int:
    let read = value.status
    let first = read()
    return first + read()

fn borrowed_owner() Unit:
    let value = marker(4)
    let answer = borrow(value)
    print("borrowed {answer}")

    let _still_present = value.id

fn shared(var value: Marker) Int:
    let bump = value.bump
    let first = bump()
    return first + bump(1)

fn shared_owner() Unit:
    var value = marker(5)
    let answer = shared(var value)
    print("shared {answer}")

    let _still_present = value.id

export fn main() Int:
    let a = ordinary()
    print("ordinary {a}")

    let b = defaulted()
    print("default {b}")

    let c = generic()
    print("generic {c}")
    borrowed_owner()
    print("after borrowed")
    shared_owner()
    print("after shared")
    return 0

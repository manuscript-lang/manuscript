// Scalar resource captures require close metadata even without drop glue.
// Borrowed parameter and projected receivers must share a pointer-only native thunk.
// expect-mir: "fn @is_error"
import Closeable, print from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!:
        print("closed-{self.id}")
        return ok(unit)

fn marked(id: Int) Int!Marker: error(Marker(id))

fn inspect(result: Int!Marker) Bool:
    let check = result.is_error
    return check() and check()

type Holder:
    result: Int!Marker

fn inspect_projected(holder: Holder) Bool:
    let check = holder.result.is_error
    return check() and check()

fn owned() Bool:
    let check = marked(1).is_error
    return check() and check()

fn borrowed() Bool:
    let result = marked(2)
    let checked = inspect(result)
    print("after-borrow")
    return checked and result.is_error()

fn projected() Bool:
    let holder = Holder(marked(3))
    let checked = inspect_projected(holder)
    print("after-projected-borrow")
    return checked and holder.result.is_error()

fn plain() Int:
    let value = 5
    let absolute = value.abs
    return absolute() + absolute()

export fn main() Int:
    if owned() and borrowed() and projected(): return plain() - 10

    return 1

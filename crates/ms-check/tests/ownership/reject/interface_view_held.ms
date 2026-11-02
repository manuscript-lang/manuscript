type Cause:
    code: Int
    text: String

impl Error for Cause:
    fn message() String: "cause {self.code}: {self.text}"

fn first_error(cause: Cause) Error:
    return cause

fn relay(e: Error) Error:
    return e

fn keep(var xs: List[Error], e: Error) Unit:
    xs.append(e)

fn store_local(cause: Cause) List[Error]:
    let e: Error = cause
    return [e]  # error: cannot move `e` out: it only borrows its value (a borrow)

fn change_held(var cause: Cause) Error:
    let e: Error = cause
    cause.code = 2  # error: cannot change `cause.code` while `e` borrows it (binding of a view of it, at 22:9)
    return e

fn store_call(var xs: List[Error], cause: Cause) Unit:
    xs.append(first_error(cause))  # error: `first_error` returns a reference into `cause`, which this position would keep

fn pass_on(var xs: List[Error], cause: Cause) Unit:
    keep(var xs, first_error(cause))  # error: `first_error` returns a reference into `cause`, which this position would keep

fn caller_change() String:
    var c = Cause(1, "x")
    let e = first_error(c)
    c.code = 3  # error: cannot change `c.code` while `e` borrows it (binding of a part of it, at 34:9)
    return e.message()

fn rebound_still_used(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    let message = e.message()
    return e2  # error: cannot move `e2` out: it only borrows its value (a borrow)

fn rebound_alias_still_used(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    let message = e.message()
    return relay(e2)  # error: `relay` returns a reference into `e`, which this position would keep

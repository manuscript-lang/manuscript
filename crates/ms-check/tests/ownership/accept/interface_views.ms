type Cause:
    code: Int
    text: String

impl Error for Cause:
    fn message() String: "cause {self.code}: {self.text}"

type Holder:
    err: Error
    cause: Cause

fn first_error(cause: Cause) Error:
    return cause

fn first_failure(cause: Cause) Int!:
    return error(cause)

fn fresh(cause: Cause, make: Bool) Error:
    if make: return Cause(9, "fresh")

    return cause

fn failing(cause: Cause) Int!Cause:
    return error(cause)

fn widened(cause: Cause) Int!:
    return failing(cause)

fn tried(cause: Cause) Int!:
    let v = try failing(cause)
    return ok(v + 1)

fn relay(e: Error) Error:
    return e

fn held(cause: Cause) String:
    let e: Error = cause
    return e.message()

fn through(cause: Cause) Error:
    let e = first_error(cause)
    return e

fn cond(cause: Cause, other: Cause, c: Bool) Error:
    let e = first_error(cause)
    if c: return e

    return other

fn maybe(cause: Cause, b: Bool) Error?:
    if b: return cause

    return none

fn either(r: Holder, b: Bool) Error:
    if b: return r.err

    return r.cause

fn owned_copy(cause: Cause) List[Error]:
    let e: Error = cause.clone()
    return [e]

fn id[T](x: T) T:
    return x

fn lend_then_relay(cause: Cause) Error:
    let e = first_error(cause)
    return relay(e)

fn lend_id(cause: Cause) Error:
    return id(first_error(cause))

fn rebound(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    return e2

fn rebound_result(cause: Cause) Int!:
    let r: Int! = error(cause)
    let r2 = r
    return r2

fn rebound_alias_relay(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    return relay(e2)

fn demo(var c: Cause) String:
    let one = first_error(c)
    let two = first_failure(c)
    let e: Error = c
    let r = relay(c)
    let text = "{one.message()} {two.err().message()} {e.message()} {r.message()} {held(c)} {through(c).message()} {lend_then_relay(c).message()} {lend_id(c).message()} {rebound(c).message()} {rebound_result(c).err().message()} {rebound_alias_relay(c).message()}"
    c.code = 5
    return text

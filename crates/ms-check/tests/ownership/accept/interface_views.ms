type Cause:
    code: Int
    text: String

impl Reportable for Cause:
    fn message() String: "cause {self.code}: {self.text}"

type Holder:
    err: Reportable
    cause: Cause

fn first_error(cause: Cause) Reportable:
    return cause

fn first_failure(cause: Cause) Int!Reportable:
    return error(cause)

fn fresh(cause: Cause, make: Bool) Reportable:
    if make: return Cause(9, "fresh")

    return cause

fn failing(cause: Cause) Int!Cause:
    return error(cause)

fn tried(cause: Cause) Int!Cause:
    let v = try failing(cause)
    return ok(v + 1)

fn relay(e: Reportable) Reportable:
    return e

fn held(cause: Cause) String:
    let e: Reportable = cause
    return e.message()

fn through(cause: Cause) Reportable:
    let e = first_error(cause)
    return e

fn cond(cause: Cause, other: Cause, c: Bool) Reportable:
    let e = first_error(cause)
    if c: return e

    return other

fn maybe(cause: Cause, b: Bool) Reportable?:
    if b: return cause

    return none

fn either(r: Holder, b: Bool) Reportable:
    if b: return r.err

    return r.cause

fn owned_copy(cause: Cause) List[Reportable]:
    let e: Reportable = cause.clone()
    return [e]

fn id[T](x: T) T:
    return x

fn lend_then_relay(cause: Cause) Reportable:
    let e = first_error(cause)
    return relay(e)

fn lend_id(cause: Cause) Reportable:
    return id(first_error(cause))

fn rebound(cause: Cause) Reportable:
    let e: Reportable = cause
    let e2 = e
    return e2

fn rebound_result(cause: Cause) Int!Reportable:
    let r: Int!Reportable = error(cause)
    let r2 = r
    return r2

fn rebound_alias_relay(cause: Cause) Reportable:
    let e: Reportable = cause
    let e2 = e
    return relay(e2)

fn demo(var c: Cause) String:
    let one = first_error(c)
    let two = first_failure(c)
    let e: Reportable = c
    let r = relay(c)
    let text = "{one.message()} {two.err().message()} {e.message()} {r.message()} {held(c)} {through(c).message()} {lend_then_relay(c).message()} {lend_id(c).message()} {rebound(c).message()} {rebound_result(c).err().message()} {rebound_alias_relay(c).message()}"
    c.code = 5
    return text

interface Reportable:
    fn message() String

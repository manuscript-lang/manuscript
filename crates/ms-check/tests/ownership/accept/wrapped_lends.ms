type Row:
    name: String
    tags: List[String]

type Bad:
    why: String

impl Reportable for Bad:
    fn message() String: self.why.clone()

# A part wrapped into an Optional or a Result on the way out is a reference to it.
fn first_tag(r: Row) String?:
    return r.tags[0]

fn named(r: Row) String!Bad:
    return ok(r.name)

fn relay(result: Row!Bad) Row!Bad:
    return result

# `try` of a lending call hands a lent error on; its payload is a reference too.
fn tail(result: Row!Bad) String!Bad:
    let row = try relay(result)
    return ok(row.name)

fn risky(n: Int) Int!Bad:
    if n < 0: return error(Bad("negative"))

    return ok(n)

# A wrapped part beside a new value (the error of `try risky`) is a new value, as before.
fn checked(r: Row, n: Int) String!Bad:
    let _v = try risky(n)
    return ok(r.name)

fn demo(r: Row, result: Row!Bad) Int:
    let o: String? = r.name
    let k: Row!Bad = ok(r)
    let again: Row!Bad = relay(result)
    return (
        o.get().length()
        + r.name.length()
        + k.get().name.length()
        + again.get().name.length()
        + first_tag(r).get().length()
        + named(r).get().length()
        + tail(result).get().length()
    )

interface Reportable:
    fn message() String

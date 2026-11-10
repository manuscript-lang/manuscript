// conform: tags=diagnostics,functions,tier-core
// conform: phase=check
// conform: origin=issue 3211
fn identity(value: Int) Int: value

fn join(first: String, second: String) String: first + second

fn _hidden(_value: Int) Int: _value

fn numbered(_0: Int, _1: Int) Int: _0 + _1

export fn main() Int:
    transform: fn(Int) Int = identity
    combine: fn(String, String) String = join
    keep: fn(Int) Int = _hidden
    text := combine(first: "a", second: "b")
    other := combine("a")
    direct := _hidden(other: 1)
    named := numbered(value: 2)
    short := numbered(_0: 1)
    return transform(value: 2) + keep(1)

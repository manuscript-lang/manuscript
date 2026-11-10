// conform: tags=diagnostics,functions,tier-core
// conform: phase=check
// conform: origin=issue 3211
fn identity(value: Int) Int: value

fn join(first: String, second: String) String: first + second

fn _hidden(_value: Int) Int: _value

fn numbered(_0: Int, _1: Int) Int: _0 + _1

export fn main() Int:
    let transform: fn(Int) Int = identity
    let combine: fn(String, String) String = join
    let keep: fn(Int) Int = _hidden
    let text = combine(first: "a", second: "b")
    let other = combine("a")
    let direct = _hidden(other: 1)
    let named = numbered(value: 2)
    let short = numbered(_0: 1)
    return transform(value: 2) + keep(1)

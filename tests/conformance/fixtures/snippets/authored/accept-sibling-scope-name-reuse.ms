// conform: tags=control-flow,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    var total = [1, 2].sum()
    for i in [3, 4]:
        total += i

    _x := 1

    if total > 0:
        _x := 2
        total += _x

    return total

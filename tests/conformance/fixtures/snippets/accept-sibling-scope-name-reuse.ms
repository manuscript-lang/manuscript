# conform: tags=control-flow,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    var total = 0
    for i in [1, 2]:
        total += i
    for i in [3, 4]:
        total += i

    let _x = 1

    if total > 0:
        let _x = 2
        total += _x

    return total

// conform: tags=diagnostics
// conform: phase=check
fn choose(value: Int) Int:
    return value
fn collect(fallback: Int = choose(1)) String:
    callbacks := [
        fn(value: Int = choose(2)) Int:
            if value > 0:
                return choose(3)
            else:
                return choose(4)
    ]
    text := "{choose(5)}"
    match fallback:
        _:
            return "{choose(6)}"
interface Read:
    fn read(value: Int) Int
type Box:
    value: Int = choose(7)
impl Read for Box:
    fn read(value: Int = choose(8)) Int:
        return choose(9)

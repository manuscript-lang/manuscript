fn shout(s: String) Unit:
    print(s)

fn report(xs: List[String]) Unit:
    xs.for_each(shout)

fn closure(xs: List[String]) List[String]:
    return xs.map(fn(s): s.upper())

fn closure_prints(xs: List[String]) Unit:
    xs.for_each(fn(s): print(s))

fn main() Unit:
    return

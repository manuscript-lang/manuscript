fn shout(s: String) Void:
    print(s)

fn report(xs: List[String]) Void:
    xs.for_each(shout)

fn closure(xs: List[String]) List[String]:
    return xs.map(fn(s): s.upper())

fn closure_prints(xs: List[String]) Void:
    xs.for_each(fn(s): print(s))

fn main() Void:
    return

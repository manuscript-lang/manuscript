interface Shape:
    fn label() String

type Sq:
    name: String

impl Shape for Sq:
    fn label() String:
        return self.name.clone()

type Holder:
    s: Shape

fn describe(s: Shape) String:
    return s.label()

fn count(items: List[Shape]) Int:
    return items.length()

fn through[T: Shape](x: T) String:
    return describe(x)

export fn main() Int:
    let q = Sq(name: "sq")

    # A read-only argument borrows, so `q` stays usable.
    if describe(q) + q.name != "sqsq":
        return 1
    if through(q) != "sq":
        return 3

    # Stored positions move at the last use or take a clone.
    let s: Shape = q.clone()
    let h = Holder(s: q.clone())
    if s.label() + h.s.label() != "sqsq":
        return 4
    if count([Sq(name: "b"), q]) != 2:
        return 5

    return 0

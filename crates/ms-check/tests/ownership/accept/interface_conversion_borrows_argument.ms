interface Shape:
    fn label() String

type Sq:
    name: String

fn Sq.label() String:
    return self.name.clone()

fn describe(s: Shape) String:
    return s.label()

fn use_twice(q: Sq) String:
    a := describe(q)
    b := describe(q)
    return a + b + q.name

type Holder:
    s: Shape

fn store(q: Sq) Holder:
    return Holder(s: q)

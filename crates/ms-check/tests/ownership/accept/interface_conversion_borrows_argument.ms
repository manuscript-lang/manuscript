interface Shape:
    fn label() String

type Sq:
    name: String

impl Shape for Sq:
    fn label() String:
        return self.name.clone()

fn describe(s: Shape) String:
    return s.label()

fn use_twice(q: Sq) String:
    let a = describe(q)
    let b = describe(q)
    return a + b + q.name

type Holder:
    s: Shape

fn store(q: Sq) Holder:
    return Holder(s: q)

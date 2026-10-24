interface Shape:
    def label() -> String

type Sq:
    name: String

impl Shape for Sq:
    def label() -> String:
        return self.name.clone()

def describe(s: Shape) -> String:
    return s.label()

def use_twice(q: Sq) -> String:
    let a = describe(q)
    let b = describe(q)
    return a + b + q.name

type Holder:
    s: Shape

def store(q: Sq) -> Holder:
    return Holder(s: q)

interface Shape:
    def label() -> String

type Sq:
    name: String

impl Shape for Sq:
    def label() -> String:
        return self.name.clone()

def describe(s: Shape) -> String:
    return s.label()

def use(q: Sq) -> String:
    return describe(Shape(value: q))  # error: cannot be constructed

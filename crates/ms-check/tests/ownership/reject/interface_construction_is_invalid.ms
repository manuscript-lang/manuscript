interface Shape:
    fn label() String

type Sq:
    name: String

fn Sq.label() String:
    return self.name.clone()

fn describe(s: Shape) String:
    return s.label()

fn use(q: Sq) String:
    return describe(Shape(value: q))  // error: cannot be constructed

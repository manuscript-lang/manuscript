interface Named:
    fn names() List[String]

type Box:
    items: List[String]

impl Named for Box:
    fn names() List[String]:
        return self.items

fn f(var b: Box) Int:
    let xs = b.names()
    b.items = []  # error: cannot change `b.items` while `xs` borrows it
    return xs.length()

interface Named:
    def names() -> List[String]

type Box:
    items: List[String]

impl Named for Box:
    def names() -> List[String]:
        return self.items

def f(var b: Box) -> Int:
    let xs = b.names()
    b.items = []  # error: cannot change `b.items` while `xs` borrows it
    return xs.length()

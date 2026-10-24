interface Named:
    def names() -> List[String]

type Box:
    items: List[String]

impl Named for Box:
    def names() -> List[String]:
        return self.items

def read(n: Named) -> Int:
    let xs = n.names()
    return xs.length()

def passes(n: Named) -> Int:
    return n.names().length()

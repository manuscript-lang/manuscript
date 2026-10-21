interface Named:
    fn names() List[String]

type Box:
    items: List[String]

impl Named for Box:
    fn names() List[String]:
        return self.items

fn read(n: Named) Int:
    let xs = n.names()
    return xs.length()

fn pass(n: Named) Int:
    return n.names().length()

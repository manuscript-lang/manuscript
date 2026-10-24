interface Shape:
    def label() -> String

type Sq:
    name: String

impl Shape for Sq:
    def label() -> String:
        return self.name.clone()

type Holder:
    s: Shape

def store(q: Sq) -> String:
    let h = Holder(s: q)  # error: moved here but used again
    return h.s.label() + q.name

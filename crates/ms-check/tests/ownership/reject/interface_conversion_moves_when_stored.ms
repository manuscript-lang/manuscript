interface Shape:
    fn label() String

type Sq:
    name: String

impl Shape for Sq:
    fn label() String:
        return self.name.clone()

type Holder:
    s: Shape

fn store(q: Sq) String:
    let h = Holder(s: q)  # error: moved here but used again
    return h.s.label() + q.name

interface Names:
    fn names() ref List[String]

type Box:
    items: List[String]

impl Names for Box:
    fn names() ref List[String]:
        return self.items

fn make() Names:
    return Box(items: [])

fn via(n: Names) ref List[String]:
    return n.names()

fn from_temporary() ref List[String]:  # error: no `return` gives back part
    return make().names()

# Passing `b` where `Names` is expected makes a new interface value holding a copy of it.
fn converted(b: Box) ref List[String]:  # error: no `return` gives back part
    return via(b)

type Holder:
    b: Box

impl Holder:
    # Returning `self.b` as `Names` converts it: the interface value is new, not a part.
    fn view() ref Names:  # error: no `return` gives back part
        return self.b

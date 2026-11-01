type Person:
    name: String

fn name_of(p: Person) String:
    return p.name

fn make() Person:
    return Person(name: "tmp")

fn keep() List[String]:
    var out: List[String] = []
    out.append(name_of(make()))
    return out

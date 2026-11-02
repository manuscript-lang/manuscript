type Person:
    name: String
    tags: List[String]

fn first_tag(p: Person) String:
    return p.tags[0]

fn collect(p: Person) List[String]:
    var out: List[String] = []
    out.append(first_tag(p))  # error: returns a reference into `p`
    return out

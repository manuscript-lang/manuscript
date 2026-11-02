type Person:
    name: String
    tags: List[String]

fn first_tag(p: Person) String:
    return p.tags[0]

fn change(var p: Person) Int:
    let t = first_tag(p)
    p.tags.append("x")  # error: cannot change `p.tags` while `t` borrows it
    return t.length()

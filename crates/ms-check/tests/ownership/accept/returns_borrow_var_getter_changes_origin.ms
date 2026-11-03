type Team:
    members: List[String]

fn members(t: Team) List[String]:
    return t.members

fn grow(var t: Team) Int:
    var ms = members(t)
    ms.append("dan")
    return t.members.length()

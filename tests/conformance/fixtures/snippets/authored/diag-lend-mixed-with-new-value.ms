# conform: tags=diagnostics,mutation,strings,tier-core
# conform: phase=check
# conform: origin=proposals/reference-ownership.md
type User:
    name: String

fn display(u: User, anonymous: Bool) String:
    if anonymous: return "anonymous"
    return u.name

fn keep(u: User) List[String]:
    return [display(u, false)]

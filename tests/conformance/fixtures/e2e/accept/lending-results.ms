# conform: tags=ownership,records,lists,tier-io
# conform: phase=run
# conform: origin=proposals/reference-ownership.md
import stdout from "@std/io/io.ms"

type Person:
    name: String
    tags: List[String]

type Team:
    members: List[Person]
    label: String

# Every path returns a part of an argument: the result is a reference into it.
fn first_tag(p: Person) String:
    return p.tags[0]

fn pick(a: Person, b: Person, left: Bool) String:
    if left: return a.name
    return b.name

fn head(rows: List[List[Int]]) List[Int]:
    let h = rows[0]
    return h

fn deep(t: Team) String:
    return first_tag(t.members[0])

fn members(t: Team) List[Person]:
    return t.members

fn recurse(value: String, count: Int) String:
    if count == 0: return value
    return recurse(value: value, count: count - 1)

fn make_team() Team:
    return Team(members: [Person(name: "ann", tags: ["x", "y"])], label: "L")

export fn main() Int:
    let p = Person(name: "bob", tags: ["t1", "t2"])
    let q = Person(name: "cat", tags: ["u1"])
    let t = first_tag(p)
    stdout().write("{t} {pick(p, q, false)} {pick(p, q, true)}\n").get()
    let rows = [[1, 2], [3]]
    let h = head(rows)
    stdout().write("{h.length()} {h[1]}\n").get()
    var team = Team(members: [p, q], label: "team")
    stdout().write("{deep(team)} {members(team).length()}\n").get()
    # A lend from a temporary is owned by the caller.
    let fresh = first_tag(Person(name: "tmp", tags: ["owned"]))
    let also = deep(make_team())
    stdout().write("{fresh} {also}\n").get()
    # `var` of a lent part changes the origin.
    var ms = members(team)
    ms.append(Person(name: "dan", tags: []))
    stdout().write("{team.members.length()} {recurse(value: team.label, count: 3)}\n").get()
    # Keeping a lent value is an explicit copy.
    var names: List[String] = []
    names.append(first_tag(team.members[0]).clone())
    stdout().write("{names.length()} {names[0]}\n").get()
    return 0

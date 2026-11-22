// conform: tags=records,lists,tier-core
// conform: phase=run
import print from "@std/core.ms"

type Person:
    name: String
    tags: List[String]

type Team:
    members: List[Person]

fn first_tag(p: Person) String:
    return p.tags[0]

fn deep(t: Team) String:
    return first_tag(t.members[0])

fn make_team(tag: String) Team:
    return Team(members: [Person(name: "ann", tags: [tag.clone()])])

// The lent tag is longer than an inline string, so it lives on the heap with its record: the
// caller owns a copy, and the temporary record's release must not free what `fresh` reads.
fn main() Void:
    long := "a-string-long-enough-to-live-on-the-heap-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    fresh := first_tag(Person(name: "tmp", tags: [long + "!"]))
    print(f"{fresh}")

    also := deep(make_team(long + "?"))
    print(f"{also}")

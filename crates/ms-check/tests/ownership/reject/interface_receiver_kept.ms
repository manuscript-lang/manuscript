type Name:
    text: String

interface Sized:
    fn size() Int

fn keep(move name: Name) Int:
    return name.text.length()

fn Name.size() Int:
    return keep(self)

fn total(sized: Sized) Int:
    return sized.size()

fn f() Int:
    return total(Name("a"))  // error: becomes a `Sized`, but `Name.size` keeps its receiver, which the interface borrows

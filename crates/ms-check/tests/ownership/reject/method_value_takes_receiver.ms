type Item:
    name: String

fn Item.listed() List[Item]:
    return [self]

fn f() Int:
    item := Item("a")
    again := item.listed  // error: `.listed` takes its receiver, but a function value can be called more than once
    return again().length()

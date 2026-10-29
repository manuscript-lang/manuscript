type View:
    s: ref String
    n: Int

type Bag:
    items: List[String]

fn view(b: Bag) View: View(b.items[0], 1)

fn f(b: Bag) Int:
    let v = view(b).clone()  # error: a copy would outlive
    return v.n

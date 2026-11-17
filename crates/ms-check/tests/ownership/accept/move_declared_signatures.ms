type Item:
    name: String

type Inv:
    items: List[Item]

type Log:
    count: Int

interface Sink:
    fn add(move item: Item) Int

fn Inv.add(move item: Item) Int:
    var xs = self.items.clone()
    xs.append(item)
    return xs.length()

fn Log.add(move item: Item) Int:
    return item.name.length()

fn feed(s: Sink, move item: Item) Int:
    return s.add(item)

fn named(move item: Item) Int:
    return item.name.length()

fn through(f: fn(move Item) Int, move item: Item) Int:
    return f(item)

fn f() Int:
    a := feed(Inv([]), Item("a"))
    b := feed(Log(0), Item("b"))
    c := through(named, Item("c"))
    d := through(fn move x: x.name.length(), Item("d"))
    return a + b + c + d

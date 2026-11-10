import Item from "./a.ms"
import b_item from "./b.ms"

type Box:
    items: List[Item]
    callback: fn(Item) Item
    maybe: Item?

enum Pick:
    missing
    found(item: Item)

interface Reader:
    fn read(item: Item) Item
    fn generic[Named](item: Named) Named

type Named:
    value: Int

type Generic[Named]:
    value: Named

fn identity[Named](item: Named) Named:
    return item

fn echo(item: Item) Item:
    return item

impl Box:
    fn first() Item:
        return self.items[0]

fn main() Unit:
    print(b_item())

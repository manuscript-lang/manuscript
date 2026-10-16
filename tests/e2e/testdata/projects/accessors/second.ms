import {
    Item,
    Read,
    Observed,
    generic,
    as_view
} from "./domain.ms"

impl Read[Int] for Item:
    get value -> Int:
        return self.count + 20

export fn second_view(item: Item) -> Read[Int]:
    return as_view(item)

export fn second_read(item: Item) -> Int:
    return generic(item)

export fn second_capture(item: Item) -> fn() -> Int:
    let receiver = item
    return fn() -> Int: receiver.value

impl Observed for Item:
    get length -> Int: self.count

    fn read() -> Int: self.count + 20

export fn second_observed(item: Item) -> Observed:
    return Observed(item)

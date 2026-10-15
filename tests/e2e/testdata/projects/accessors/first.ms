import {Item, Read, Observed, generic, as_view} from "./domain.ms"

impl Read[Int] for Item:
    get value -> Int:
        return self.count + 10

export fn first_view(item: Item) -> Read[Int]:
    return as_view(item)

export fn first_read(item: Item) -> Int:
    return generic(item)

export fn first_capture(item: Item) -> fn() -> Int:
    let receiver = item
    return fn() -> Int: receiver.value

impl Observed for Item:
    get length -> Int: self.count
    fn read() -> Int: self.count + 10

export fn first_observed(item: Item) -> Observed:
    return Observed(item)

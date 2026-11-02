import Item, Sized, answer, LIMIT from "./declared.ms"
import score from "./bridge.ms"

export fn total(item: Item, value: Sized) Int:
    return score(item, value) + item.value + value.size() + answer() + LIMIT

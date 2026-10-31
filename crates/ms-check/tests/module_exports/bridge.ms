import Item, Sized, answer, LIMIT from "./declared.ms"

export fn score(item: Item, value: Sized) Int:
    return item.value + value.size() + answer() + LIMIT

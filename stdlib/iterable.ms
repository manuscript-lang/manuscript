# A container that can be walked by position. `for item in container:` reads `container.length()` once
# and then `container.at(index)` for each index, binding each `item` as an owned value; an item that is
# only read is not copied.
export interface Iterable[T]:
    # Returns the number of items.
    fn length() Int
    # Returns the item at `index` counted from the first, or none when out of range.
    fn at(index: Int) T?

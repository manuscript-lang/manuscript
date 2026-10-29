# A container whose items can be read in place by position. `for item in container:` walks
# `0..length()` and binds each `at(index)` as a borrow, so an item is never cloned and `T` needs no
# `Clonable`. `length()` is read once; an index that is out of range by then is skipped. A type that
# also implements `Iterator` iterates with `Iterator`.
export interface Indexed[T]:
    # Returns the number of items.
    fn length() Int
    # Returns a borrow of the item at `index` counted from the first, or none when out of range.
    fn at(index: Int) ref Optional[T]

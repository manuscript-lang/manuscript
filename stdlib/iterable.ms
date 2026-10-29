# A container that can be walked by borrow. `for item in container:` calls `container.iter()` and
# iterates the result, so `item` borrows the container's value in place: nothing is cloned and `T`
# needs no `Clonable`. The container stays unchanged until the loop's last use of its items.
# `I` is the iterator type, an `Iterator` whose `next` lends from the container it was made from.
export interface Iterable[I]:
    # Returns an iterator over the container's items, borrowing the container.
    fn iter() I

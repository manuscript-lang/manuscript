# A container that can be walked. `for item in container:` calls `container.iter()` and iterates the
# result, binding each `item` as an owned value; an item that is only read is not copied.
# `I` is the iterator type, an `Iterator` made from the container.
export interface Iterable[I]:
    # Returns an iterator over the container's items.
    fn iter() I

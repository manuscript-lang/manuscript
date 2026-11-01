import Pair from "@std/collections/collections.ms"
import panic from "@std/core.ms"

# Combinatorial and sequence helpers over lists, in the spirit of Python's `itertools`.
# Every function builds a new list of copies and leaves its inputs unchanged, so the elements must be Clonable.
# Results that grow combinatorially (`permutations`, `combinations`, `product`) are built whole: bound the input size.
# `itertools.pairwise([1, 2, 3])` pairs each item with the next one. Chunking and sliding windows are `List.chunks` and `List.windows`.

# A run of consecutive items that share a key, from `group_runs`.
export type Run[K: Clonable, T: Clonable]:
    # The key shared by every item in the run.
    key: K
    # The items of the run in their original order.
    items: List[T]

# Pairs each item with the one after it; a list with fewer than two items gives an empty list.
# Example: `pairwise([1, 2, 3])` holds the pairs `(1, 2)` and `(2, 3)`.
export fn pairwise[T: Clonable](values: List[T]) List[Pair[T, T]]:
    var out: List[Pair[T, T]] = []
    for i in 1..values.length():
        out.append(Pair(values[i - 1].clone(), values[i].clone()))
    return out

# Returns the running results of folding `step` over the items: the first item, then `step(first, second)`, and so on.
# The result has as many items as the input; an empty list gives an empty list.
# Example: `accumulate([1, 2, 3, 4], fn a, b: a + b)` is `[1, 3, 6, 10]`.
export fn accumulate[T: Clonable](values: List[T], step: fn(T, T) T) List[T]:
    var out: List[T] = []

    for i in 0..values.length():
        if i == 0:
            out.append(values[0].clone())
        else:
            out.append(step(out[i - 1].clone(), values[i].clone()))

    return out

# Repeats the whole list `times` times in order. A negative `times` faults; zero gives an empty list.
# Example: `cycle([1, 2], 3)` is `[1, 2, 1, 2, 1, 2]`.
export fn cycle[T: Clonable](values: List[T], times: Int) List[T]:
    if times < 0:
        panic("cycle: times must not be negative")

    var out: List[T] = []
    for unused1 in 0..times:
        for value in values:
            out.append(value.clone())
    return out

# Pairs items by position and pads the shorter list with none, so the result is as long as the longer list.
# Example: `zip_longest([1, 2, 3], ["a"])` pairs `(1, "a")`, `(2, none)` and `(3, none)`.
export fn zip_longest[A: Clonable, B: Clonable](
    left: List[A],
    right: List[B]
) List[Pair[A?, B?]]:
    var out: List[Pair[A?, B?]] = []
    var longest = left.length()
    if right.length() > longest:
        longest = right.length()

    for i in 0..longest:
        var first: A? = none
        var second: B? = none
        if i < left.length():
            first = left[i].clone()
        if i < right.length():
            second = right[i].clone()
        out.append(Pair(first, second))

    return out

# Splits the list into runs of consecutive items whose `key` is equal (Python `itertools.groupby`); `key` is called once per item in order.
# Items with the same key that are not adjacent form separate runs: sort first to gather them. An empty list gives an empty list.
# Example: `group_runs([1, 1, 2, 1], fn n: n)` has the runs `1 1`, `2` and `1`.
export fn group_runs[T: Clonable, K: Equal & Clonable](
    values: List[T],
    key: fn(T) K
) List[Run[K, T]]:
    var out: List[Run[K, T]] = []

    for value in values:
        let k = key(value)
        let count = out.length()

        if count > 0 and out[count - 1].key == k:
            out[count - 1].items.append(value.clone())
        else:
            out.append(Run(key: k, items: [value.clone()]))

    return out

# Returns every ordering of `size` items chosen from the list, in lexicographic order of position; items are distinguished by position, not value.
# Omit `size` for full-length orderings. A `size` outside 0 through the list length faults.
# Example: `permutations([1, 2, 3], 2)` is `[[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]`.
export fn permutations[T: Clonable](values: List[T], size: Int? = none) List[List[T]]:
    let n = values.length()
    let k = size.get(n)
    if k < 0 or k > n:
        panic("permutations: size must be from 0 to the list length")

    var out: List[List[T]] = []
    var used: List[Bool] = []
    var chosen: List[Int] = []
    for unused2 in 0..n:
        used.append(false)
    extend_permutations(values, k, var used, var chosen, var out)
    return out

fn extend_permutations[T: Clonable](
    values: List[T],
    k: Int,
    var used: List[Bool],
    var chosen: List[Int],
    var out: List[List[T]]
) Unit:
    if chosen.length() == k:
        out.append(chosen.map(fn i: values[i].clone()))
        return

    for i in 0..values.length():
        if not used[i]:
            used.set(i, true)
            chosen.append(i)
            extend_permutations(values, k, var used, var chosen, var out)
            chosen.pop()
            used.set(i, false)

# Returns every selection of `size` items in their original order, in lexicographic order of position; items are distinguished by position, not value.
# A `size` outside 0 through the list length faults.
# Example: `combinations([1, 2, 3], 2)` is `[[1, 2], [1, 3], [2, 3]]`.
export fn combinations[T: Clonable](values: List[T], size: Int) List[List[T]]:
    if size < 0 or size > values.length():
        panic("combinations: size must be from 0 to the list length")

    var out: List[List[T]] = []
    var chosen: List[Int] = []
    extend_combinations(values, size, 0, var chosen, var out)
    return out

fn extend_combinations[T: Clonable](
    values: List[T],
    k: Int,
    start: Int,
    var chosen: List[Int],
    var out: List[List[T]]
) Unit:
    if chosen.length() == k:
        out.append(chosen.map(fn i: values[i].clone()))
        return

    for i in start..values.length():
        chosen.append(i)
        extend_combinations(values, k, i + 1, var chosen, var out)
        chosen.pop()

# Returns the cartesian product: one list per way of taking one item from each input list, in lexicographic order, the last list varying fastest.
# No input lists gives one empty combination; any empty input list gives an empty result.
# Example: `product([[1, 2], [3, 4]])` is `[[1, 3], [1, 4], [2, 3], [2, 4]]`.
export fn product[T: Clonable](lists: List[List[T]]) List[List[T]]:
    var out: List[List[T]] = [[]]

    for choices in lists:
        var next: List[List[T]] = []

        for prefix in out:
            for item in choices:
                var combo = prefix.clone()
                combo.append(item.clone())
                next.append(combo)

        out = next

    return out

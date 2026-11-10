// Borrowed list helpers must not acquire an implicit owning copy for scalar iteration.
// expect-mir: "list.len"
fn first[T](rows: List[List[T]]) List[T]:
    return rows[0]

export fn main() Int:
    rows := [[1, 2], [3, 4]]
    var total = 0
    for value in first(rows):
        total += value
    return total

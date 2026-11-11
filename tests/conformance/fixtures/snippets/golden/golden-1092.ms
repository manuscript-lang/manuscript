// conform: tags=diagnostics
// conform: phase=check
fn work() Bool:
    return [[1, 2], [3]].flat_map(transform: fn(value: List[Int]) List[Int]: return value) == [1, 2, 3]

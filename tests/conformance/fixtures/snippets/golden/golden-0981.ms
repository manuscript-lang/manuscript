// conform: tags=diagnostics
// conform: phase=check
fn broken(
fn later(values: List[Int]) Int:
    result := match values[0]:
        number:
            doubled := number * 2
            doubled
        none: return 0
    return result

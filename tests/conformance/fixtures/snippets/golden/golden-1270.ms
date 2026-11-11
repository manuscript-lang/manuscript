// conform: tags=diagnostics
// conform: phase=check
fn read(values: List[Int], index: Int) Int:
    result := match values.take(index).first():
        number:
            doubled := number * 2
            doubled
        none: 0
    return result

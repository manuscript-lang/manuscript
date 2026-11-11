// conform: tags=diagnostics
// conform: phase=check
fn read(values: List[Int]) Int:
    let result=match values.first():
        number:
            let doubled=number*2
            doubled
        none: return 0
    return result

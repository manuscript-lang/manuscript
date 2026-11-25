// conform: tags=diagnostics
// conform: phase=check
fn read(values List[Int]) Int {
    let result=match values.first() {
        number => {
            let doubled=number*2
            doubled
        }
        null => return 0
    }
    return result
}
// expect-error: MS1000 4:5-4:16 'let' was removed; bind with 'x := value' (or 'x Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding
// expect-fix: 4:5-4:16 "result :="

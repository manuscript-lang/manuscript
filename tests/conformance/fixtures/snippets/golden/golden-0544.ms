// conform: tags=diagnostics
// conform: phase=check
values List[Int] = []
    var fill = 0
    while fill < 100 {
        values.append(fill)
        fill += 1
    }
// expect-error: MS1000 3:18-3:19 an immutable binding uses ':=' after its type: write 'x Type := value'; '=' binds only after 'var'
// expect-fix: 3:18-3:19 ":="

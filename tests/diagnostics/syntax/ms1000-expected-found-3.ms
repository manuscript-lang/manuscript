// conform: tags=diagnostics
// conform: phase=check
x := match 0 {
            n => {
                sum = start
                n
            }
            null => 0
        sum += i
        i += 1
}
// expect-error: MS1000 9:13-9:14 expected '=>', found '+'
// expect-error: MS1000 10:11-10:12 expected '=>', found '+'

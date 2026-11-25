// conform: tags=diagnostics
// conform: phase=check
    var i%d = 0
    while i%d < 1000 {
        if found := affine%d(i%d) {
            sum += found
        } else {
            sum -= 1
        }
        i%d += 1
    }
// expect-error: MS1000 3:5-3:8 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

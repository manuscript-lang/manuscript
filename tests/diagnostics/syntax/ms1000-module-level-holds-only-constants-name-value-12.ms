// conform: tags=diagnostics
// conform: phase=check
    var i = 0
    while i < 4 {
        read := fn() Int {
            return values.get(0)
        }
        total += read()
        i += 1
    }
// expect-error: MS1000 3:5-3:8 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

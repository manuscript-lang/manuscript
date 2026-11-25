// conform: tags=diagnostics
// conform: phase=check
var value = 1
    values := [1].map(fn(item) {
        value = 2
        return item
    }
    )
// expect-error: MS1000 3:1-3:4 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

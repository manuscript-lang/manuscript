// conform: tags=diagnostics
// conform: phase=check
var sum = 0
    var i = 0
    while i < 1000 {
        if found := 
    }
// expect-error: MS1000 3:1-3:4 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

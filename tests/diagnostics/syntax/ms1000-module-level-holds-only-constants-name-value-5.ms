// conform: tags=diagnostics
// conform: phase=check
var i = 0
    captured := match 0 {
        n => {
            i = start
            n
        }
        null => 0
    }
// expect-error: MS1000 3:1-3:4 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

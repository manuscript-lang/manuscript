// conform: tags=diagnostics
// conform: phase=check
var stride = 3
    read := fn() Int => stride
    stride = 3
    sum = 0
    i = 0
// expect-error: MS1000 3:1-3:4 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

// conform: tags=diagnostics
// conform: phase=check
    alias := shapes
    var sum
// expect-error: MS1000 4:5-4:8 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

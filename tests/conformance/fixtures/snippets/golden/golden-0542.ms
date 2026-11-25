// conform: tags=diagnostics
// conform: phase=check
values := [1]
    var fill = 0
    while fill < 100 {
        values.append(values.get(-1) + 1)
        fill += 1
    }
// expect-error: MS1000 4:5-4:8 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type
// expect-error: MS1000 5:5-5:10 expected a module declaration or import, found 'while'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 8:5-8:6 unmatched closing delimiter '}'; remove it or add the matching opener before it

// conform: tags=diagnostics
// conform: phase=check
original := fn(item Int) => item
    incompatible: fn(value: Int) Int = original
// expect-error: MS1000 4:17-4:18 remove the ':' between 'incompatible' and its type; write incompatible Type
// expect-fix: 4:17-4:18 ""

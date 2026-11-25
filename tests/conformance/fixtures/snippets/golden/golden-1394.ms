// conform: tags=diagnostics
// conform: phase=check
fn valid() Void {
}
var invalid = 3
// expect-error: MS1000 4:1-4:2 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration
// expect-error: MS1000 5:1-5:4 module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type

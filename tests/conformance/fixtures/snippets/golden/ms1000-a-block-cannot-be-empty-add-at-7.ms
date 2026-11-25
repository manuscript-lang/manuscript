// conform: tags=diagnostics
// conform: phase=check
test "empty" {
}
// expect-error: MS1000 4:1-4:2 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration

// conform: tags=diagnostics,interpolation,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/text-and-bytes.md:39
name := "Ada"
count := 3
greeting := f"Welcome, {name}!"
calculated := f"Next: {count + 1}"
// expect-exit: 0

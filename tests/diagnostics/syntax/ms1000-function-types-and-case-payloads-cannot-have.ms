// conform: tags=diagnostics
// conform: phase=check
enum F {
    Value(value Int = 1)
}
// expect-error: MS1000 4:21-4:22 function types and case payloads cannot have defaults; put the default on a named function parameter or a type field instead

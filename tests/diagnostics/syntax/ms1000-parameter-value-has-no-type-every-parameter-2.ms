// conform: tags=diagnostics
// conform: phase=check
enum Choice {
    Payload(value)
}
// expect-error: MS1000 4:13-4:18 parameter 'value' has no type; every parameter is written name Type, e.g. value Int

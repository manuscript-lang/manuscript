// conform: tags=diagnostics
// conform: phase=check
test "fault":
    missing: Int? := null
    impossible := missing.get()

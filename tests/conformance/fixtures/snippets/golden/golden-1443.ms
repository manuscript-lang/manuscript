// conform: tags=diagnostics
// conform: phase=check
test "fault":
    missing: Int? := none
    impossible := missing.get()

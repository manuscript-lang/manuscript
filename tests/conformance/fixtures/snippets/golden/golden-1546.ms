// conform: tags=diagnostics
// conform: phase=check
test "positive unit overflow":
    impossible := (153722868).minutes()
test "negative unit overflow":
    impossible := (-153722868).minutes()
test "receiver fault comes first":
    impossible := (1 / 0).minutes()
test "continues with valid units":
    valid := (1).seconds()

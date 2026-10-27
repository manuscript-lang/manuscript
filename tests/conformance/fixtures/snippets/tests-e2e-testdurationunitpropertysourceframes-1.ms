# conform: tags=testing,tier-core,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/unit_property_locations_test.go:13 TestDurationUnitPropertySourceFrames
test "positive unit overflow":
    let _impossible = (153722868).minutes

test "negative unit overflow":
    let _impossible = (-153722868).minutes

test "receiver fault comes first":
    let _impossible = (1 / "".byte_length()).minutes

test "continues with valid units":
    let _valid = (1).seconds

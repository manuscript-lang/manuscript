# conform: tags=testing,tier-core,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/unit_property_locations_test.go:13 TestDurationUnitPropertySourceFrames
test "positive unit overflow":
    let impossible = (153722868).minutes

test "negative unit overflow":
    let impossible = (-153722868).minutes

test "receiver fault comes first":
    let impossible = (1 / 0).minutes

test "continues with valid units":
    let valid = (1).seconds

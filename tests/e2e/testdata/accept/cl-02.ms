fn invalid_division(zero: Int) -> Bool:
    return 1 / zero == 0

test "grouping and short circuit":
    assert 2 + 3 * 4 == 14
    assert (2 + 3) * 4 == 20
    assert 10 - 3 - 2 == 5
    assert true or invalid_division(zero: 0)
    assert not (false and invalid_division(zero: 0))

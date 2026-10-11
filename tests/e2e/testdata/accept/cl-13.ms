fn echo(value: String) -> String:
    return value

test "text source forms":
    assert echo(value: "\{literal\}") == "\{literal\}"
    assert "\u{1F600}" == "😀"
    assert "value: {3}" == "value: 3"
    let no_value: Unit = unit

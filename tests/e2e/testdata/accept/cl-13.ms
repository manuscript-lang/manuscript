import panic from "@std/faults.ms"

fn echo(value: String) -> String:
    return value

test "text source forms":
    if not (echo(value: "\{literal\}") == "\{literal\}"):
        return panic(message: "check failed")
    if not ("\u{1F600}" == "😀"):
        return panic(message: "check failed")
    if not ("value: {3}" == "value: 3"):
        return panic(message: "check failed")

    let no_value: Unit = unit

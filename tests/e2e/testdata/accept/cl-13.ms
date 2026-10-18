import panic from "@std/faults.ms"

fn echo(value: String) String:
    return value

test "text source forms":
    if not (echo("\{literal\}") == "\{literal\}"):
        return panic("check failed")
    if not ("\u{1F600}" == "😀"):
        return panic("check failed")
    if not ("value: {3}" == "value: 3"):
        return panic("check failed")

    let _no_value: Unit = unit

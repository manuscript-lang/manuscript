import Error from "@std/errors.ms"
import panic from "@std/faults.ms"

type Result:
    diagnostic: String

impl Error for Result:
    fn message() -> String:
        return self.diagnostic

fn general(value: Result) -> Error:
    return value

test "an application error named Result retains its nominal identity":
    let original = Result("application diagnostic")
    let cause = general(original)
    if cause.message() != "application diagnostic":
        return panic(message: "application Result was treated as a standard Result")

    match cause:
        Result(receiver):
            receiver.diagnostic = "changed diagnostic"

        _:
            return panic(message: "application Result lost concrete type")

    if original.diagnostic != "changed diagnostic":
        return panic(message: "Error boundary copied application Result")

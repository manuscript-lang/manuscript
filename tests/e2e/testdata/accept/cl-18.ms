import panic from "@std/faults.ms"

fn apply(value: Int, transform: fn(value: Int) Int) Int:
    return transform(value: value)

test "function suite boundaries":
    let _dormant = fn():
        return panic(message: "body is not run at creation")
    let grouped = apply(
        transform: (
            fn(value):
                if value > 0:
                    return value - 1

                return 0
        ),
        value: 3
    )
    let final_argument = apply(
        value: 3,
        transform: fn(value):
            return value - 1
    )
    if not (grouped == 2):
        return panic(message: "check failed")
    if not (final_argument == 2):
        return panic(message: "check failed")

// A Result whose error borrows an argument while its ok payload is a new value.
fn grow(value: String!String) String!String:
    let output = try value
    return ok(output + "x")

// `try` of a borrowing result relays the borrowed error and owns the ok payload.
fn relay(value: String!String) String!String:
    let text = try grow(value)
    return ok(text + "y")

// A borrowing result returned whole is the same borrowing result.
fn pass_on(value: String!String) String!String:
    return grow(value)

fn length(value: String!String) Int:
    match grow(value):
        ok(text): return text.length()
        error(cause): return cause.length()

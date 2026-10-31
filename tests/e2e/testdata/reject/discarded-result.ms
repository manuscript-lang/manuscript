fn parse(text: String) Int!:
    return ok(1)

# A statement that drops a Result loses its failure; `let _ =` drops it on purpose.
export fn main() Int:
    parse("1")
    return 0

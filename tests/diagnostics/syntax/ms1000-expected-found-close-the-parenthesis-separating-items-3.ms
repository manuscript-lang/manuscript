// conform: tags=diagnostics
// conform: phase=check
f fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int?, timeout: Duration?) Result[CommandOutput, CommandError] = commands().run
    f(program: "", arguments: [])
// expect-error: MS1000 3:13-3:14 expected ')', found ':'; close the parenthesis, separating items with commas

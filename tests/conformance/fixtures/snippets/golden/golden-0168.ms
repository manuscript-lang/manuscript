// conform: tags=diagnostics
// conform: phase=check
f: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int?, timeout: Duration?) Result[CommandOutput, CommandError] = commands().run
    f(program: "", arguments: [])
# conform: tags=closures,lists,optional,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/native_defaults_test.go:25 TestNativeDefaultCallableBoundaries
let f: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Optional[Int], timeout: Optional[Duration]) Result[CommandOutput, CommandError] = commands().run
    f(program: "", arguments: [])

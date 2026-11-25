// conform: tags=diagnostics
// conform: phase=check
fn probe(input ReadStream, visits List[Int]) Bool { ... }
// expect-error: MS2001 3:16 unknown type ReadStream; add: import ReadStream from "@std/io/io.ms"
// expect-fix: 1:1-1:1 "import ReadStream from \"@std/io/io.ms\"\n"
// expect-error: MS3000 3:1 reachable fallthrough in function returning Bool; end every path with 'return <Bool>' (or make the last branch return)

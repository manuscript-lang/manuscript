// conform: tags=diagnostics
// conform: phase=check
type Data {
    fn read() Int {
    }
}
// expect-error: MS1000 4:5-4:7 a type declares only fields; write its methods after it as 'fn Data.name(...)'

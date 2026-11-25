// conform: tags=diagnostics
// conform: phase=check
import %s from "@std/%s.ms"
test "reject" {
    value := %s()
}
// expect-error: MS1000 3:8-3:9 expected a name, found '%'
// expect-error: MS1000 5:14-5:15 expected an expression, found '%'; write a value, name, call, or literal here

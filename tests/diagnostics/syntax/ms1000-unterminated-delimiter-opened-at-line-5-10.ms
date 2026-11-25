// conform: tags=diagnostics
// conform: phase=check
import value from "./local.ms"
fn helper() Int => return 3
fn broken(
// expect-error: MS1000 7:1 unterminated delimiter '(' opened at line 5:10; add the matching ')' before the end of the file

// conform: tags=diagnostics
// conform: phase=check
import ListBuilder, List from "@std/collections/collections.ms"
fn broken(
// expect-error: MS1000 6:1 unterminated delimiter '(' opened at line 4:10; add the matching ')' before the end of the file

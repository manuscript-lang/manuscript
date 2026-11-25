// conform: tags=diagnostics
// conform: phase=check
add := values.add
size := add(1, 2).length()
// expect-error: MS3070 3:15 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 4:19 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS2001 3:8 unknown binding values; add: import values from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import values from \"@std/bytes.ms\"\n"

// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/numbers-and-booleans.md:10
count := 3
ratio := 0.5
price := 12.50d
active := true
// expect-error: MS2002 6:10 Decimal literal requires the canonical Decimal import; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"

// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/numbers-and-booleans.md:86
price := 100d
percent := 15d
discounted := price * (1d - percent / 100d)
// expect-error: MS2002 4:10 Decimal literal requires the canonical Decimal import; add: import Decimal from "@std/math/decimal.ms"
// expect-fix: 1:1-1:1 "import Decimal from \"@std/math/decimal.ms\"\n"

// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:424 TestRejectedModuleBoundaries
import read from "./main.ms"
// expect-error: MS2002 4:1 cannot find module ./main.ms (looked for main.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file

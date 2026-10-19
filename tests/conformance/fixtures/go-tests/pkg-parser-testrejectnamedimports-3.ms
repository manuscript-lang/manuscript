# conform: tags=modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:181 TestRejectNamedImports
import { A,, B } from "./mod.ms"

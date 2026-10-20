# conform: tags=modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:185 TestRejectNamedImports
import { A as B } from "./mod.ms"

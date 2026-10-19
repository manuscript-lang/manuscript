# conform: tags=modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:123 TestPreludeImportCompletionSpacingAndRecovery
fn bad() Unit:
   unit
import {ListBuilder, List} from "@std/collections.ms"

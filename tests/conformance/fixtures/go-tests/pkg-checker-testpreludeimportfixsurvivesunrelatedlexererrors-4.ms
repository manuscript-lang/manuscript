# conform: tags=modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:176 TestPreludeImportFixSurvivesUnrelatedLexerErrors
fn bad() Unit:
   unit
import List from "@std/collections.ms"

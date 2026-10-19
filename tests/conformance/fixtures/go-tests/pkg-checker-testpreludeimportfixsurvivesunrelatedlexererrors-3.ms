# conform: tags=modules,parser,stdlib-collections,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:175 TestPreludeImportFixSurvivesUnrelatedLexerErrors
import List from "@std/collections.ms"
fn bad() String: "unterminated

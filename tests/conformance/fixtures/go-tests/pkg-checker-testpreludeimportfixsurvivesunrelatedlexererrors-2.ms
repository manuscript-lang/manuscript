# conform: tags=modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:174 TestPreludeImportFixSurvivesUnrelatedLexerErrors
import {ListBuilder, List} from "@std/collections.ms"
fn broken(

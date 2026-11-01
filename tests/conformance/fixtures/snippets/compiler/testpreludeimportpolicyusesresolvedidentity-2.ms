# conform: tags=diagnostics,lists,maps,modules,sets,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:157 TestPreludeImportPolicyUsesResolvedIdentity
import List, Map, Set from "@std/collections/collections.ms"

fn get() Int: List[Int]().length() + Map[Int, Int]().length() + Set[Int]().length()

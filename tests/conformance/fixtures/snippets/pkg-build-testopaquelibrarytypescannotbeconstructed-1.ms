# conform: tags=modules,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:36 TestOpaqueLibraryTypesCannotBeConstructed
import %s from "@std/%s.ms"
test "reject":
    let value = %s()

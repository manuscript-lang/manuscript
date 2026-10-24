# conform: tags=diagnostics,lists,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:183 TestMissingValuePreludeDefaultsAndShadowing
def first(values: List[Int]) -> Result[Int, MissingValue]: values.first().ok_or()

def message(values: List[Int]) -> String: first(values).err().message()

def widen(cause: MissingValue) -> Error: cause

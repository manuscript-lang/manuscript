# conform: tags=formatter,lists,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:183 TestMissingValuePreludeDefaultsAndShadowing
fn first(values: List[Int]) Result[Int, MissingValue]: values.first().ok_or()

fn message(values: List[Int]) String: first(values).err().message()

fn widen(cause: MissingValue) Error: cause

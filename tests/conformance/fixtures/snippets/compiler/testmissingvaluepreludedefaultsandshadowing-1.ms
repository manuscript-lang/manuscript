# conform: tags=diagnostics,lists,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/collection_prelude_imports_test.go:183 TestMissingValuePreludeDefaultsAndShadowing
fn first(values: List[Int]) Int!: values.first().ok_or()

fn message(values: List[Int]) String: first(values).err().message

fn kind(values: List[Int]) ErrorCategory: first(values).err().kind

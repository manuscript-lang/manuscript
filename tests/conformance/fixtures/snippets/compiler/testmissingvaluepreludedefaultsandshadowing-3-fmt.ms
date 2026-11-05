// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:203 TestMissingValuePreludeDefaultsAndShadowing
enum Other:
    Missing(value: Int)

fn get() Other: Missing(1)

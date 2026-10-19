# conform: tags=closures,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:28 TestResultTypeRejectsArrowAndOmission
interface Read:
    fn read() -> Int

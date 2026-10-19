# conform: tags=interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:30 TestResultTypeRejectsArrowAndOmission
interface Read:
    fn read()

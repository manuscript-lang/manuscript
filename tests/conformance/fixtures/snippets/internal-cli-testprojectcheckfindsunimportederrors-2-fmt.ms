# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=internal/cli/project_check_test.go:17 TestProjectCheckFindsUnimportedErrors
def number() -> Int:
    return "wrong"

def text() -> String:
    return 1

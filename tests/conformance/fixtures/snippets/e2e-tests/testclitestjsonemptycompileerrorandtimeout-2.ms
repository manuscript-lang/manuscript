# conform: tags=diagnostics,testing,tier-core
# conform: phase=check
# conform: origin=tests/e2e/cli_json_test.go:127 TestCLITestJSONEmptyCompileErrorAndTimeout
test "bad":
    let x = unknown_name

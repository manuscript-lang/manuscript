# conform: tags=diagnostics,interpolation,lists,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:161 TestFormatMultilineFunctionParameters
export fn render(
    arguments:List[String], # arguments
    output:WriteStream,
) Int:
    let message="Arguments: {arguments.join(",")}\n"
    match output.write(data: message):
        ok(_):
            return 0
        error(_):
            return 1

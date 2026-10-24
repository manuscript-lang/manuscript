# conform: tags=formatter,interpolation,lists,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_test.go:162 TestFormatMultilineFunctionParameters
export def render(
    arguments: List[String],  # arguments
    output: WriteStream,
) -> Int:
    let message = f"Arguments: {arguments.join(",")}\n"

    match output.write(data: message):
        case ok(_):
            return 0
        case error(_):
            return 1

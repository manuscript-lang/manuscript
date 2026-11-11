// conform: tags=diagnostics
// conform: phase=check
fn work() Bool:
    return Error(value: CommandError.Failed(message: "command diagnostic")).message() != "command diagnostic"

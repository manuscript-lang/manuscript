// conform: tags=diagnostics
// conform: phase=check
fn wrong() Result[Unit, JsonError]:
    return error(cause: EncodingError.InvalidData)

# conform: tags=formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/modules/declarations.md:75
type PrivateToken:
    value: String

# Rejected: callers cannot name the internal result type.
export def issue() -> PrivateToken:
    return PrivateToken("token")

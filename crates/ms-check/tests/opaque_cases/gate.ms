export opaque type Token:
    case Minted
    case Labeled(text: String)

export fn mint() Token:
    return Minted

export fn label(text: String) Token:
    return Labeled(text)

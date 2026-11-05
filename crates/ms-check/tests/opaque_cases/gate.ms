export opaque enum Token:
    Minted
    Labeled(text: String)

export fn mint() Token:
    return Minted

export fn label(text: String) Token:
    return Labeled(text)

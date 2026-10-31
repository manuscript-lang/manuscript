import Token from "./gate.ms"

export fn fabricate() Token:
    return Labeled("untrusted")

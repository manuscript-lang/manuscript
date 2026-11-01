import Sealed, Token, Plain, Choice from "./types.ms"

export fn observe(value: Sealed[Int], token: Token) Bool:
    return value.accepts() and value.precedes(3) and token.valid()

export fn construct_public() Int:
    let plain = Plain()
    let choice = Choice.Filled(plain.visible)

    match choice:
        Filled(payload): return payload
        Vacant: return 0

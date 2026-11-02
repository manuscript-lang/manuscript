import Token from "./gate.ms"

export type Visible:
    case Minted
    case Labeled(value: Int)

export fn mint() Visible:
    return Minted

export fn label() Visible:
    return Labeled(1)

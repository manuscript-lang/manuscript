import Token from "./gate.ms"

export enum Visible:
    Minted
    Labeled(value: Int)

export fn mint() Visible:
    return Minted

export fn label() Visible:
    return Labeled(1)

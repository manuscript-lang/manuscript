export enum Status:
    Ready
    Busy(value: Int)
    bare_variant

opaque enum private:
    Hidden

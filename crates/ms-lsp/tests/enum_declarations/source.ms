export enum Status:
    case Ready
    case Busy(value: Int)

opaque enum private:
    case Hidden

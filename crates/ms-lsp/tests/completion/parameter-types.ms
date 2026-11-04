type Packet[T]:
    value: T

fn receive[T](
    data: Packet[T],
    extra: T
) Int:
    return 0

fn defaults(
    data: Packet[Int] = Packet(1)
) Int:
    return 0

fn make(
    value: Int
) Packet[Int]:
    return Packet(value)

fn inline(amount: Int) Int: return amount

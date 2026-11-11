type Payload:
    value: Int

type Envelope[T]:
    data: T
    nested: Payload
    defaulted: Payload = Payload(1)

enum Choice[T]:
    Data(value: T, nested: Payload)
    Empty

fn receive[T](
data: T,
packet: Payload
) Int:
    return 0

type Box[A]:
    value: A

fn Box[A].receive[T](data: T) Int:
    return 0

fn Box[A].owned(data: A) Int:
    return 0

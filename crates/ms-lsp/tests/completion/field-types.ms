type Payload:
    value: Int

type Envelope[T]:
    data: T
    nested: Payload
    defaulted: Payload = Payload(1)

enum Choice[T]:
    case Data(value: T, nested: Payload)
    case Empty

fn receive[T](
data: T,
packet: Payload
) Int:
    return 0

type Box[A]:
    value: A

impl Box[A]:
    fn receive[T](data: T) Int:
        return 0

    fn owned(data: A) Int:
        return 0

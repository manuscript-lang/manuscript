interface Reader:
    fn read[T](value: T) T

type Source:
    number: Int

fn Source.read[PARAMETER](value: PARAMETER) PARAMETER:
    return value

interface Reader:
    fn read[T](value: T) T

type Source:
    number: Int

impl Reader for Source:
    fn read[PARAMETER](value: PARAMETER) PARAMETER:
        return value

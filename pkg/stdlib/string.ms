# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned by Unicode scalar conversions and bounded string operations.
export type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)

# The four Unicode normalization forms, selected without runtime string spelling errors.
export type NormalizationForm:
    # Canonical decomposition followed by canonical recomposition where Unicode permits it.
    case Nfc
    # Canonical decomposition with combining marks placed in canonical order.
    case Nfd
    # Compatibility decomposition followed by canonical recomposition where Unicode permits it.
    case Nfkc
    # Compatibility decomposition with combining marks placed in canonical order.
    case Nfkd

    # Normalizes text with the existing String.normalize budgets and StringError cases.
    # Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.
    fn normalize(
        text: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]:

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) -> Result[String, StringError]:

impl Error for StringError:
    fn message() -> String:

# Mutable builder for constructing a string without repeated intermediate copies.
# Mutable builder for constructing a string without repeated intermediate copies.
export type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:

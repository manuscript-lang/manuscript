# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned by Unicode scalar conversions and bounded string operations.
export type StringError:
    # Scalar values, normalization form or a supplied repeat/padding/output budget is invalid.
    case InvalidInput
    # A strict scalar slice bound lies outside the string or its range is inverted.
    case OutOfRange
    # UTF-8 output exceeds a supplied byte budget or the native string allocation limit.
    case LimitExceeded
    # A string-domain failure with an explicit diagnostic supplied by an implementation.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) -> Result[String, StringError]:

impl Error for StringError:
    # Returns original Failed text, or a string-prefixed diagnostic for other cases.
    fn message() -> String:

# Mutable builder for constructing a string without repeated intermediate copies.
export type StringBuilder:
    # Appends the supplied text in order; mutation after freeze raises a sealed-builder fault.
    fn append(value: String) -> Unit:
    # Seals the builder and returns immutable text; repeated freeze returns the same text value.
    fn freeze() -> String:

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

impl NormalizationForm:
    # Normalizes text with the existing String.normalize budgets and StringError cases.
    # Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.
    fn normalize(
        text: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]:

# Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.
export fn from_scalars(values: List[Int]) -> Result[String, StringError]:

impl Error for StringError:
    # Returns original Failed text, or a string-prefixed diagnostic for other cases.
    fn message() -> String:

# Mutable builder for constructing a string without repeated intermediate copies.
export type StringBuilder:

impl StringBuilder:
    # Appends the supplied text in order; mutation after freeze raises a sealed-builder fault.
    fn append(value: String) -> Unit:

    # Seals the builder and returns immutable text; repeated freeze returns the same text value.
    fn freeze() -> String:

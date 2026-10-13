# Canonical standard-library declarations. Implementations are native.

# An exact decimal value. Conversions are explicit because binary floats may round.
export type Decimal:
    fn to_float() -> Float:
    fn truncate_to_int() -> Optional[Int]:

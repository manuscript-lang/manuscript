# Expected failures share this explicitly implemented diagnostic contract.

export interface Error:
    fn message() -> String

export fn as_error[E: Error](cause: E) -> Error

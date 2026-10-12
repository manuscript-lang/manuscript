# Expected failures share this explicitly implemented diagnostic contract.

export interface Error:
    fn message() -> String

# Expected failures share this explicitly implemented diagnostic contract.

# A contract for expected failures that can provide a human-readable message.
export interface Error:
    # Returns a human-readable description of this expected error.
    fn message() -> String

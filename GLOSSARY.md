# Manuscript glossary

For definitions and links across the language, see the [plain-language glossary](design/glossary.md).

## Functions and sharing

**Shared function**: a function value the compiler has proved safe to invoke concurrently because its captures and bound receiver are safe to share. This is a retained proof about the value; a source function type does not itself guarantee sharing. Captured resources can still close while references to them remain.

See [callable sharing rules](design/ownership-and-cleanup/values/sharing.md#function-values). Use “shared function” rather than “parallel function”; the caller chooses whether to run it concurrently.

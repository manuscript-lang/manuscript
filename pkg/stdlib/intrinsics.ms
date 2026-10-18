# Source locations for the fixed intrinsic receiver operations.
import StringError from "@std/string.ms"
import NumberError from "@std/numbers.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"

# Every value has this operation, including unconstrained type parameters.
interface ValueOperations:
    fn toString() -> String

# Data values have a shallow clone returning the concrete receiver type.
interface CloneOperations[T]:
    fn clone() -> T

# String receiver operations use UTF-8 text. Methods named `scalar_*` count Unicode
# scalar values; ordinary indices and lengths count Unicode scalar positions unless
# the method explicitly refers to bytes.
interface StringOperations:
    # Counts Unicode scalars, with the same unit as scalar_length.
    fn length() -> Int
    # Reports whether the text contains no scalars.
    fn is_empty() -> Bool
    # Returns a fresh list with one String for each Unicode scalar, in order.
    fn chars() -> List[String]
    # Reverses Unicode scalar order; combining sequences/graphemes may change.
    fn reverse() -> String
    # Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.
    fn compare(other: String) -> Int
    # Splits LF and CRLF lines, preserving interior empty lines and standalone CR.
    # Omits a final extra empty item; empty text returns a fresh empty list.
    fn lines() -> List[String]
    # Normalizes using exactly NFC, NFD, NFKC, or NFKD (case-sensitive); max_bytes optionally bounds UTF-8 output.
    # Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.
    fn normalize(
        form: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Concatenates text without changing either operand.
    fn concat(other: String) -> String
    # Tests whether the exact text occurs, without normalization.
    fn contains(value: String) -> Bool
    # Tests whether the receiver ends with this exact suffix.
    fn ends_with(suffix: String) -> Bool
    # Returns locale-independent full Unicode lowercase mapping; the scalar length can change.
    fn lower() -> String
    # Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.
    fn repeat(
        count: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Transitional compatibility name: omitted or none replaces the first occurrence; an explicit cap can replace more.
    # Use replace_n for a required finite cap; this retained signature has not become a strict first-only operation.
    # An empty old matches at scalar boundaries, and inserted text is not searched again.
    # Zero changes nothing; negative caps retain replace's programming fault.
    fn replace_first(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Replaces at most the required number of nonoverlapping literal occurrences; zero leaves text unchanged.
    # Empty old matches at scalar boundaries, inserted text is not rescanned, and negative caps retain replace's programming fault.
    # The count limits replacements, not UTF-8 output bytes; there is no additional allocation budget.
    fn replace_n(old: String, new: String, max_replacements: Int) -> String
    # Compatibility spelling for replace_first, including its explicit replacement cap.
    fn replace(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Returns the number of Unicode scalar values in the string.
    fn scalar_length() -> Int
    # Returns each Unicode scalar value as an integer.
    fn scalar_values() -> List[Int]
    # Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length().
    # Negative, inverted, or out-of-range bounds return StringError.OutOfRange.
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    # Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
    # Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]
    # Tests whether the receiver begins with this exact prefix.
    fn starts_with(prefix: String) -> Bool
    # Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.
    fn trim() -> String
    # Returns locale-independent full Unicode uppercase mapping; the scalar length can change.
    fn upper() -> String
    # Returns a one-scalar String; negative indexes are relative to the end, and invalid indexes return none.
    fn at(index: Int) -> Optional[String]
    # Returns an integer scalar code point; negative indexes are relative to the end, and invalid indexes return none.
    fn scalar_at(index: Int) -> Optional[Int]
    # Returns the first matching Unicode scalar index or none; empty value matches at zero.
    fn index_of(value: String) -> Optional[Int]
    # Returns the last matching Unicode scalar index or none; empty value matches at scalar_length().
    fn last_index_of(value: String) -> Optional[Int]
    # Removes Unicode whitespace at the start.
    fn trim_start() -> String
    # Removes Unicode whitespace at the end.
    fn trim_end() -> String
    # Pads on the left until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; max_bytes still bounds UTF-8 output.
    fn pad_start(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Pads on the right until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; negative targets/budgets return InvalidInput.
    fn pad_end(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Replaces every nonoverlapping occurrence; empty old matches at each scalar boundary.
    # max_bytes bounds UTF-8 output; negatives return InvalidInput and exhaustion returns LimitExceeded.
    fn replace_all(
        old: String,
        new: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Selects [start, end) in Unicode scalars; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= scalar_length() return StringError.OutOfRange; the receiver is unchanged.
    fn slice(start: Int, end: Int) -> Result[String, StringError]
    # Returns the UTF-8 encoded byte length.
    fn byte_length() -> Int
    # Encodes the string as UTF-8 bytes.
    fn to_bytes() -> Bytes
    # Parses signed ASCII decimal digits; invalid text or Int overflow returns none.
    fn parse_int() -> Optional[Int]

# Conversion operations for machine-sized integers.
interface IntOperations:
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string(radix: Int) -> String
    # Converts to the nearest Float; integers beyond 2^53 in magnitude can lose low-order digits.
    fn to_float() -> Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() -> Decimal
    # Returns -1, 0 or 1 as this value is less than, equal to or greater than `other`.
    fn compare(other: Int) -> Int

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    # Formats 1..100 significant digits, preserving trailing zeros; an invalid precision returns NumberError.InvalidInput.
    fn to_precision(precision: Int) -> Result[String, NumberError]
    # Formats scientific notation with 0..100 fractional digits; an invalid count returns NumberError.InvalidInput.
    fn to_exponential(digits: Int) -> Result[String, NumberError]
    # Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
    # Invalid digits return NumberError.InvalidInput; rounding uses binary64 ties to even.
    fn to_fixed(digits: Int) -> Result[String, NumberError]
    # Returns the shortest round-trip representation, including NaN and signed infinities.
    fn to_string() -> String
    # Tests whether the value is NaN.
    fn is_nan() -> Bool
    # Tests whether the value is neither NaN nor an infinity.
    fn is_finite() -> Bool
    # Returns -1, 0 or 1 in a total order: -0.0 equals 0.0, and NaN is equal to NaN and greater than every other value, including +Inf.
    fn compare(other: Float) -> Int
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    fn truncate_to_int() -> Optional[Int]
# Contributor notes: source ownership and editor integration.
# # Standard-library declarations
#
# The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Modules with ordinary function or implementation bodies are written in Manuscript and checked and lowered with each importing program. Go supplies the native implementations for declaration-only modules; integration tests check that their calling signatures agree with the Manuscript declarations.
#
# ## Which file defines what?
#
# - The `.ms` files define the type schemas and public API.
# - Native functions dispatch to `module/name`; `bindings.json` lists only the exceptions under `function_overrides`, and maps receiver-operation and implementation identities directly to native dispatch. It also records method-specific receiver requirements, such as `Equal` for list searches and `String` for list joining; it does not duplicate operation signatures or type schemas.
# - `intrinsics.ms` contains private operation declarations for primitive receivers and the universal `toString()` method.
# - Native receiver signatures appear once, on their type or intrinsic interface. TaskGroup and Task[T] use ordinary generic declarations; no private free-function declarations are needed for their implementations.
#
# These files use ordinary Manuscript syntax. Runtime functions and receiver operations have empty function bodies, written with the usual colon, such as `export fn commands() -> Commands:`. Opaque type schemas use empty declarations such as `export type Duration:`. Interface signatures remain signatures, and `bindings.json` maps the declarations to native implementations. The checker verifies implementation rules and native signatures. There is no library-only parser mode or `native` keyword. Ordinary record fields may have default expressions.
#
# Defaults follow the checked declarations. Source functions evaluate omitted defaults in the callee; native functions and ordinary record constructors receive values prepared at the call site. Mutable default values are created afresh. See the canonical default-argument rules and typed Go lowering guide for supported expressions and evaluation order.
#
# Modules with executable bodies use the ordinary checker and need no entries in `bindings.json`. Imports include their reachable source implementations once, with the same public visibility and type identities as application modules.
#
# Keep a module's implementation ownership consistent: adding an executable body marks the whole module as source-owned. A typed adapter in an existing declaration-only module should use its native binding path; one source helper body does not preserve that module's other native declarations or nominal identities.
#
# ## Editor navigation
#
# Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.
#
# Hover documentation lives in contiguous `#` comments immediately above a public declaration or operation. The LSP renders this text as Markdown beneath the checked Manuscript signature. Keep the opening sentence direct, then describe behavior that is not clear from the signature: units, defaults, limits, mutation, end-of-stream behavior, and expected errors. Inline Markdown such as code spans is supported.
#
# The generated Markdown/JSON reference also reads comments above fields, cases, and receiver/implementation operations. Keep each block at the member's indentation; a blank line detaches it. JSON preserves the original string arrays and adds structured `members` descriptions. Document case payloads by placing each parameter and its comment on an indented line inside the parentheses; a case description does not describe its fields implicitly.
#
# `make docs` and `make docs-check` report description counts and enforce the description gate. `make docs-coverage` writes the complete inventory to `.artifacts/stdlib-doc-coverage.json`, including prelude aliases. Presence and structural quality are separate counts: empty text, placeholders, very terse labels, and name/kind restatements fail quality checks. Review each description against source/native behavior; passing structural checks cannot prove semantic accuracy or measure a separate tutorial's coverage.
#
# `pkg/tooling/docgen/description_backlog.json` records exact existing gaps during #176's sweep. This temporary list only shrinks: new gaps fail, invalid prose cannot use it, and described/removed entries make the old key stale. It is not an internal/generated exemption. Public synthetic primitive entries require descriptions too. Private `ValueOperations`/`CloneOperations` are implementation declarations; their universal calls remain non-importable. No blanket public-description exemption is supported.
#
# These APIs provide navigation data; an editor integration must supply its own LSP server and transport.
#
# Platform helpers in `internal/hostos/` are bundled with native dependency sources.
#
# Time values and sequential `sleep` live in `@std/time.ms`. `@std/tasks.ms` owns `Scheduler`, which manages immediate, delayed, and repeating work through one operation-ID lifecycle, plus TaskGroup, Task[T], cancellation checks, and scheduler yielding. Limits and deadlines use optional values; receiver operations are the single public API for existing data.

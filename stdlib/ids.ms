# Identifiers that the type checker keeps apart. `Id[User]` and `Id[Order]` hold the same kind of text but are different types,
# so passing an order id where a user id is expected is a compile-time error, and each works as a `Map` key or `Set` member.
#
# ```manuscript
# def load_user(id: Id[User]) -> Result[User, LoadError]: ...
#
# let id = try id_from[User]("u-42")
# ```
# The tag type is never stored; any type declaration works, such as `type User: name: String`.
# Why identifier text was rejected.
export type IdError:
    # The text is empty, longer than 256 bytes, or holds a control character.
    case InvalidText

impl Error for IdError:
    # Returns `id: invalid text`.
    def message() -> String: "id: invalid text"

# An identifier for a `T`, distinct from the identifier of every other type. Prefer `id_from`, which validates the text.
export type Id[T]:
    # The identifier text, 1 to 256 bytes without control characters when built by `id_from`.
    value: String

# Builds an `Id[T]` from text that is nonempty, at most 256 bytes and free of control characters (U+0000 through U+001F and U+007F).
export def id_from[T](text: String) -> Result[Id[T], IdError]:
    if text.is_empty() or text.length() > 256: return error(IdError.InvalidText)

    for scalar in text.scalar_values():
        if scalar < 32 or scalar == 127: return error(IdError.InvalidText)
    return ok(Id[T](text))

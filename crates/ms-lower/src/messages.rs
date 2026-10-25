// Message text of every standard error case; keep in sync with `stdlib/*.ms`.

use crate::iface::Message::{self, Payload, Text};

/// The `message()` text of each case of a standard error type.
pub(crate) fn table(name: &str) -> Option<&'static [(&'static str, Message)]> {
    Some(match name {
        "BinaryError" => &[
            ("InvalidInput", Text("binary: invalid input")),
            ("OutOfRange", Text("binary: value out of range")),
        ],
        "CollectionError" => &[
            ("InvalidInput", Text("collection: invalid input")),
            ("LimitExceeded", Text("collection: limit exceeded")),
            ("OutOfRange", Text("collection: value out of range")),
        ],
        "RandomError" => &[
            ("InvalidInput", Text("random: invalid input")),
            ("LimitExceeded", Text("random: limit exceeded")),
            ("Failed", Payload),
        ],
        "RegexError" => &[
            ("InvalidInput", Text("regular expression: invalid input")),
            ("InvalidData", Text("regular expression: invalid data")),
            ("LimitExceeded", Text("regular expression: limit exceeded")),
        ],
        "StringError" => &[
            ("InvalidInput", Text("string: invalid input")),
            ("OutOfRange", Text("string: value out of range")),
            ("LimitExceeded", Text("string: limit exceeded")),
            ("Failed", Payload),
        ],
        _ => return None,
    })
}

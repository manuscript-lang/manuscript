// Mutable builder for constructing a string without repeated intermediate copies.
export extern type StringBuilder

// Appends the supplied text in order.
fn var StringBuilder.append(value: String) Void: ...

// Consumes the builder and returns its text; the builder cannot be used afterwards.
fn move StringBuilder.build() move String: ...

// Returns the text appended so far and leaves the builder empty, for a builder held
// in a field.
fn var StringBuilder.drain() move String: ...

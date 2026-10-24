# Encoder state behind `@std/log.ms`. Import that module instead; these declarations are its native base.
# Errors the encoder returns; `@std/log.ms` maps them to `LogError`.
export type LogCoreError:
    # A level is outside Trace through Fatal, or a size budget is negative.
    case InvalidInput
    # Structured fields are not a JSON object or cannot be encoded.
    case InvalidData
    # An encoded record exceeds the size budget.
    case LimitExceeded

# A logger's threshold, bound fields, and record settings.
export type LogState: ...

impl LogState:
    # Returns state that adds the members of the JSON object text `fields` to each record.
    def child(fields: String) -> Result[LogState, LogCoreError]: ...

    # Tests whether a record at the level index would be written.
    def enabled(level: Int) -> Bool: ...

    # Returns the threshold as a level index.
    def level() -> Int: ...

    # Replaces the threshold with a level index.
    def set_level(level: Int) -> Unit: ...

    # Encodes a record line, or returns empty text when the level is below the threshold.
    def line(level: Int, message: String, now_ms: Int) -> Result[String, LogCoreError]: ...

    # Encodes a record line with the members of the JSON object text `fields` added.
    def line_json(
        level: Int,
        message: String,
        fields: String,
        now_ms: Int
    ) -> Result[String, LogCoreError]: ...

# Creates state from optional level index, timestamp setting, and record byte limit.
export def new_state(
    level: Optional[Int],
    timestamp: Optional[Bool],
    max_bytes: Optional[Int]
) -> Result[LogState, LogCoreError]: ...

# A flag every copy of a transport shares; once shut it stays shut.
export type LogGate: ...

impl LogGate:
    # Marks the gate shut for every copy of the transport; shutting it again changes nothing.
    def shut() -> Unit: ...

    # Tells whether the gate is shut.
    def is_shut() -> Bool: ...

# Creates an open gate.
export def new_gate() -> LogGate: ...

# Returns stringified JSON as an object text: an object is unchanged, anything else sits under `data`.
export def object_text(text: String) -> String: ...

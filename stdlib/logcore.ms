extern def msrt_logcore_child(
    value: LogState,
    fields: String
) -> Result[LogState, LogCoreError]

extern def msrt_logcore_enabled(value: LogState, level: Int) -> Bool

extern def msrt_logcore_level(value: LogState) -> Int

extern def msrt_logcore_set_level(value: LogState, level: Int) -> Unit

extern def msrt_logcore_line(
    value: LogState,
    level: Int,
    message: String,
    now_ms: Int
) -> Result[String, LogCoreError]

extern def msrt_logcore_line_json(
    value: LogState,
    level: Int,
    message: String,
    fields: String,
    now_ms: Int
) -> Result[String, LogCoreError]

extern def msrt_logcore_new_state(
    level: Optional[Int],
    timestamp: Optional[Bool],
    max_bytes: Optional[Int]
) -> Result[LogState, LogCoreError]

extern def msrt_logcore_shut(value: LogGate) -> Unit

extern def msrt_logcore_is_shut(value: LogGate) -> Bool

extern def msrt_logcore_new_gate() -> LogGate

extern def msrt_logcore_object_text(text: String) -> String

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
export extern type LogState

impl LogState:
    # Returns state that adds the members of the JSON object text `fields` to each record.
    def child(fields: String) -> Result[LogState, LogCoreError]:
        return msrt_logcore_child(self, fields)

    # Tests whether a record at the level index would be written.
    def enabled(level: Int) -> Bool:
        return msrt_logcore_enabled(self, level)

    # Returns the threshold as a level index.
    def level() -> Int:
        return msrt_logcore_level(self)

    # Replaces the threshold with a level index.
    def set_level(level: Int) -> Unit:
        msrt_logcore_set_level(self, level)

    # Encodes a record line, or returns empty text when the level is below the threshold.
    def line(level: Int, message: String, now_ms: Int) -> Result[String, LogCoreError]:
        return msrt_logcore_line(self, level, message, now_ms)

    # Encodes a record line with the members of the JSON object text `fields` added.
    def line_json(
        level: Int,
        message: String,
        fields: String,
        now_ms: Int
    ) -> Result[String, LogCoreError]:
        return msrt_logcore_line_json(self, level, message, fields, now_ms)

# Creates state from optional level index, timestamp setting, and record byte limit.
export def new_state(
    level: Optional[Int],
    timestamp: Optional[Bool],
    max_bytes: Optional[Int]
) -> Result[LogState, LogCoreError]:
    return msrt_logcore_new_state(level, timestamp, max_bytes)

# A flag every copy of a transport shares; once shut it stays shut.
export extern type LogGate

impl LogGate:
    # Marks the gate shut for every copy of the transport; shutting it again changes nothing.
    def shut() -> Unit:
        msrt_logcore_shut(self)

    # Tells whether the gate is shut.
    def is_shut() -> Bool:
        return msrt_logcore_is_shut(self)

# Creates an open gate.
export def new_gate() -> LogGate:
    return msrt_logcore_new_gate()

# Returns stringified JSON as an object text: an object is unchanged, anything else sits under `data`.
export def object_text(text: String) -> String:
    return msrt_logcore_object_text(text)

impl Error for LogCoreError:
    # Returns a fixed diagnostic that names the failing step.
    def message() -> String:
        match self:
            case InvalidInput: return "log core: invalid input"
            case InvalidData: return "log core: invalid data"
            case LimitExceeded: return "log core: limit exceeded"

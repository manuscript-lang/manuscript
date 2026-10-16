import JsonValue from "@std/json.ms"
import Synchronized from "@std/sync.ms"

export type Content:
    case Text(text: String)
    case Thinking(text: String)
    case Image(data: String, mime_type: String)
    case ToolCall(id: String, name: String, arguments: JsonValue)

export type Role:
    case System
    case User
    case Assistant
    case ToolResult

export type StopReason:
    case Stop
    case ToolUse
    case Length
    case Failed
    case Aborted

export type Usage:
    input: Int = 0
    output: Int = 0
    cache_read: Int = 0
    cache_write: Int = 0
    total_tokens: Int = 0
    cost: JsonValue = JsonValue.Null

export type ToolDeclaration:
    name: String
    description: String
    parameters: JsonValue
    constrained_sampling: Optional[Bool] = none

export type Message:
    role: Role
    content: List[Content] = []
    stop_reason: StopReason = StopReason.Stop
    tool_call_id: String = ""
    tool_name: String = ""
    is_error: Bool = false
    error_message: String = ""
    details: JsonValue = JsonValue.Null
    timestamp_ms: Int = 0
    usage: Optional[Usage] = none
    duration_ms: Optional[Int] = none
    model: String = ""
    provider: String = ""
    api: String = ""
    thinking_level: String = "off"
    provider_thinking_level: String = ""
    content_signatures: Map[Int, String] = Map[Int, String]()
    sections: Map[String, Optional[String]] = Map[String, Optional[String]]()
    tools_added: List[ToolDeclaration] = []
    tools_removed: List[String] = []

export type ToolResult:
    content: List[Content] = []
    details: JsonValue = JsonValue.Null
    structured_content: Optional[JsonValue] = none
    is_error: Bool = false
    terminate: Bool = false
    usage: Optional[Usage] = none
    duration_ms: Optional[Int] = none

export type ToolResultPatch:
    content: Optional[List[Content]] = none
    details: Optional[JsonValue] = none
    structured_content: Optional[JsonValue] = none
    is_error: Optional[Bool] = none
    terminate: Optional[Bool] = none
    usage: Optional[Usage] = none

export type ToolCallOutcome:
    call: ToolCall
    result: ToolResult

export type ToolCall:
    id: String
    name: String
    arguments: JsonValue
    original_arguments: Optional[JsonValue] = none
    assistant_message: Optional[Message] = none
    control: Optional[Synchronized[Control]] = none

export type ExecutionMode:
    case Sequential
    case Parallel

export type QueueMode:
    case All
    case OneAtATime

# Callbacks check this token at safe points. Use request_abort to notify waiters.
export type Control:
    aborted: Bool = false
    steering: List[Message] = []
    follow_up: List[Message] = []
    running: Bool = false
    generation: Int = 0
    completed_generation: Int = 0
    signal: Optional[Synchronized[Control]] = none

export type Tool:
    name: String
    description: String
    parameters: JsonValue
    validate: Optional[fn(arguments: JsonValue) -> Result[JsonValue, Error]] = none
    execute: fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]
    execution_mode: Optional[ExecutionMode] = none
    prepare_arguments: Optional[fn(value: JsonValue) -> Result[JsonValue, Error]] = none
    output_schema: Optional[JsonValue] = none
    replay: String = "never"
    constrained_sampling: Optional[Bool] = none
    label: String = ""
    formats: Map[String, fn(value: String) -> Bool] = Map[
        String,
        fn(value: String) -> Bool
    ]()

export type Context:
    messages: List[Message] = []
    tools: List[Tool] = []

export type Request:
    context: Context
    model: String
    thinking_level: String = "off"
    options: JsonValue = JsonValue.Null
    model_descriptor: JsonValue = JsonValue.Null
    on_payload: Optional[fn(payload: JsonValue) -> JsonValue] = none
    on_response: Optional[fn(response: JsonValue) -> Unit] = none
    provider_event: Optional[fn(event: JsonValue) -> Unit] = none
    messages: List[Message] = []

export type Turn:
    message: Message
    tool_results: List[Message]
    context: Context
    new_messages: List[Message]

export type Decision:
    case Default
    case Continue
    case End

export type Preflight:
    blocked: Bool = false
    reason: String = "Tool execution was blocked"
    terminate: Bool = false

export type Event:
    case ProviderUpdate(event: JsonValue)
    case AgentStart
    case AgentEnd(messages: List[Message])
    case TurnStart
    case TurnEnd(message: Message, tool_results: List[Message])
    case MessageStart(message: Message)
    case MessageUpdate(message: Message)
    case MessageEnd(message: Message)
    case ToolStart(call: ToolCall)
    case ToolUpdate(call: ToolCall, result: ToolResult)
    case ToolEnd(call: ToolCall, result: ToolResult)

export type StreamRuntime:
    stream: Optional[
        fn(
            request: Request,
            control: Synchronized[Control],
            update: fn(message: Message) -> Unit
        ) -> Result[Message, Error]
    ] = none

export type Config:
    # The provider emits partial snapshots through update and returns the final message.
    stream: Optional[
        fn(
            request: Request,
            control: Synchronized[Control],
            update: fn(message: Message) -> Unit
        ) -> Result[Message, Error]
    ] = none
    emit: fn(event: Event) -> Unit
    model: String = ""
    thinking_level: String = "off"
    tool_execution: ExecutionMode = ExecutionMode.Parallel
    steering_mode: QueueMode = QueueMode.OneAtATime
    follow_up_mode: QueueMode = QueueMode.OneAtATime
    transform_context: Optional[
        fn(messages: List[Message]) -> Result[List[Message], Error]
    ] = none
    convert_to_llm: Optional[
        fn(messages: List[Message]) -> Result[List[Message], Error]
    ] = none
    before_tool_call: Optional[
        fn(call: ToolCall, context: Context) -> Result[Preflight, Error]
    ] = none
    after_tool_call: Optional[
        fn(
            call: ToolCall,
            result: ToolResult,
            context: Context
        ) -> Result[ToolResult, Error]
    ] = none
    finish_turn: Optional[fn(turn: Turn) -> Decision] = none
    prepare_request: Optional[fn(request: Request) -> Request] = none
    prepare_next_turn: Optional[fn(turn: Turn) -> Request] = none
    after_tool_patch: Optional[
        fn(
            call: ToolCall,
            result: ToolResult,
            context: Context
        ) -> Result[ToolResultPatch, Error]
    ] = none
    options: JsonValue = JsonValue.Null
    model_descriptor: JsonValue = JsonValue.Null
    provider: String = ""
    api_key: String = ""
    get_api_key: Optional[fn(provider: String) -> Result[String, Error]] = none
    provider_event: Optional[fn(event: JsonValue) -> Unit] = none
    on_payload: Optional[fn(payload: JsonValue) -> JsonValue] = none
    on_response: Optional[fn(response: JsonValue) -> Unit] = none
    runtime: StreamRuntime = StreamRuntime()

export type AgentError:
    case InvalidState(message: String)

impl Error for AgentError:
    fn message() -> String:
        match self:
            InvalidState(message): return message

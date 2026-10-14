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

export type Message:
    role: Role
    content: List[Content] = []
    stop_reason: StopReason = StopReason.Stop
    tool_call_id: String = ""
    tool_name: String = ""
    is_error: Bool = false
    error_message: String = ""
    details: JsonValue = JsonValue.Null

export type ToolResult:
    content: List[Content] = []
    details: JsonValue = JsonValue.Null
    structured_content: Optional[JsonValue] = none
    is_error: Bool = false
    terminate: Bool = false

export type ToolCall:
    id: String
    name: String
    arguments: JsonValue

export type ExecutionMode:
    case Sequential
    case Parallel

export type QueueMode:
    case All
    case OneAtATime

# Callbacks poll this token at safe points, including during blocking work.
export type Control:
    aborted: Bool = false
    steering: List[Message] = []
    follow_up: List[Message] = []

export type Tool:
    name: String
    description: String
    parameters: JsonValue
    validate: fn(arguments: JsonValue) -> Result[JsonValue, Error]
    execute: fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]
    execution_mode: Optional[ExecutionMode] = none

export type Context:
    messages: List[Message] = []
    tools: List[Tool] = []

export type Request:
    context: Context
    model: String
    thinking_level: String = "off"

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

export type Config:
    # The provider emits partial snapshots through update and returns the final message.
    stream: fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]
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

export type AgentError:
    case InvalidState(message: String)

impl Error for AgentError:
    fn message() -> String:
        match self:
            InvalidState(message): return message

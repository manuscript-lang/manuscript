import {create_agent, prompt} from "./agent.ms"
import {
    Config,
    Context,
    Request,
    Control,
    Message,
    Role,
    Content,
    Event,
    Tool,
    ToolCall,
    ToolResult,
    StopReason
} from "./types.ms"
import Synchronized from "@std/sync.ms"
import JsonValue from "@std/json.ms"
import stdout from "@std/io.ms"

fn validate(arguments: JsonValue) -> Result[JsonValue, Error]:
    return ok(arguments)

fn echo(
    call: ToolCall,
    control: Synchronized[Control],
    update: fn(result: ToolResult) -> Unit
) -> Result[ToolResult, Error]:
    return ok(
        ToolResult(
            content: [Content.Text("Hello from a native Manuscript tool")]
        )
    )

fn model(
    request: Request,
    control: Synchronized[Control],
    update: fn(message: Message) -> Unit
) -> Result[Message, Error]:
    if request.context.messages.last.unwrap().role == Role.ToolResult:
        return ok(Message(Role.Assistant, [Content.Text("Done.")]))

    update(Message(Role.Assistant, [Content.Text("Calling echo…")]))
    return ok(
        Message(
            Role.Assistant,
            [Content.ToolCall("echo-1", "echo", JsonValue.Null)],
            StopReason.ToolUse
        )
    )

fn display(event: Event) -> Unit:
    match event:
        MessageEnd(message): show(message)
        _: return

fn show(message: Message) -> Unit:
    for block in message.content:
        match block:
            Text(text):
                let _written = stdout().write("{text}\n".to_bytes())
            _: continue

export fn main() -> Int:
    let tool = Tool("echo", "Demonstration tool", JsonValue.Null, validate, echo)
    let agent = create_agent(
        Config(stream: model, emit: display),
        Context(tools: [tool])
    )

    match prompt(agent, [Message(Role.User, [Content.Text("Say hello")])]):
        ok(_): return 0
        error(_): return 1

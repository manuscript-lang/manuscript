import Bytes from "@std/bytes.ms"
import IoError from "@std/io.ms"
import {
    Message,
    Role,
    Content,
    StopReason,
    Request,
    Control,
    Usage,
    AgentError
} from "./types.ms"
import {field, text} from "./schema.ms"
import content_text from "./transcript.ms"
import is_aborted from "./agent.ms"
import {JsonValue, parse, stringify} from "@std/json.ms"
import {
    HttpClient,
    HttpClientOptions,
    ResponseBody,
    HttpMethod,
    headers
} from "@std/http.ms"
import network from "@std/net.ms"
import {ReadStream, read_line, read_all} from "@std/io.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import {sleep, duration, Duration} from "@std/time.ms"

export type ProxyOptions:
    url: String
    auth_token: String = ""
    max_response_bytes: Optional[Int] = none
    max_event_bytes: Optional[Int] = none
    timeout: Optional[Duration] = none
    make_client: fn() -> Result[HttpClient, Error] = make_client

fn make_client() -> Result[HttpClient, Error]:
    return network().http_client(HttpClientOptions())

type BodyReader:
    body: ResponseBody

impl ReadStream for BodyReader:
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        return self.body.read(max_bytes)

    fn close() -> Unit: self.body.close()

fn numeric(value: Int) -> JsonValue: JsonValue.NumberValue(value.toString())

fn string(value: String) -> JsonValue: JsonValue.StringValue(value)

fn block_json(block: Content, signature: Optional[String]) -> JsonValue:
    let values = Map[String, JsonValue]()

    match block:
        Text(value):
            values.add(
                "type",
                string("text")
            ).add(
                "text",
                string(value)
            )

            if signature.is_some(): values.add(
                "textSignature",
                string(signature.unwrap())
            )
        Thinking(value):
            values.add(
                "type",
                string("thinking")
            ).add(
                "thinking",
                string(value)
            )

            if signature.is_some(): values.add(
                "thinkingSignature",
                string(signature.unwrap())
            )
        Image(data, mime): values.add(
            "type",
            string("image")
        ).add(
            "data",
            string(data)
        ).add(
            "mimeType",
            string(mime)
        )
        ToolCall(id, name, arguments): values.add(
            "type",
            string("toolCall")
        ).add(
            "id",
            string(id)
        ).add(
            "name",
            string(name)
        ).add("arguments", arguments)

    return JsonValue.ObjectValue(values)

fn role_name(role: Role) -> String:
    match role:
        System: return "system"
        User: return "user"
        Assistant: return "assistant"
        ToolResult: return "toolResult"

fn reason_name(reason: StopReason) -> String:
    match reason:
        Stop: return "stop"
        ToolUse: return "toolUse"
        Length: return "length"
        Failed: return "error"
        Aborted: return "aborted"

fn usage_json(usage: Usage) -> JsonValue:
    return JsonValue.ObjectValue(
        {
            "input": numeric(usage.input),
            "output": numeric(usage.output),
            "cacheRead": numeric(usage.cache_read),
            "cacheWrite": numeric(usage.cache_write),
            "totalTokens": numeric(usage.total_tokens),
            "cost": usage.cost
        }
    )

export fn message_json(message: Message) -> JsonValue:
    let result = Map[String, JsonValue]()
    result.add(
        "role",
        string(role_name(message.role))
    )
    result.add(
        "timestamp",
        numeric(message.timestamp_ms)
    )
    let content: List[JsonValue] = []

    for entry in message.content.entries(): content.append(
        block_json(
            entry.value,
            (message.content_signatures.get(entry.index))
        )
    )

    result.add(
        "content",
        JsonValue.ArrayValue(content)
    )

    if message.role == Role.System:
        result.add(
            "content",
            string(content_text(message.content))
        )

        if not message.sections.is_empty():
            let sections = Map[String, JsonValue]()

            for entry in message.sections.entries():
                var value = JsonValue.Null

                if entry.value.is_some(): value = string(entry.value.unwrap())

                sections.add(entry.key, value)

            result.add(
                "sections",
                JsonValue.ObjectValue(sections)
            )

        if not message.tools_added.is_empty():
            let tools: List[JsonValue] = []

            for tool in message.tools_added:
                let declaration = Map[String, JsonValue]()
                (
                    declaration.add(
                        "name",
                        string(tool.name)
                    ).add(
                        "description",
                        string(tool.description)
                    ).add("parameters", tool.parameters)
                )

                if tool.constrained_sampling.is_some(): declaration.add(
                    "constrainedSampling",
                    JsonValue.BoolValue(
                        (tool.constrained_sampling.unwrap())
                    )
                )

                tools.append(JsonValue.ObjectValue(declaration))

            result.add(
                "toolsAdded",
                JsonValue.ArrayValue(tools)
            )

        if not message.tools_removed.is_empty():
            result.add(
                "toolsRemoved",
                JsonValue.ArrayValue(
                    (
                        message
                        .tools_removed
                        .map(
                            fn(name: String) -> JsonValue: JsonValue.ObjectValue(
                                {"name": string(name)}
                            )
                        )
                    )
                )
            )

    if message.role == Role.Assistant:
        (
            result
            .add(
                "stopReason",
                string(reason_name(message.stop_reason))
            )
            .add(
                "model",
                string(message.model)
            )
            .add(
                "provider",
                string(message.provider)
            )
            .add(
                "api",
                string(message.api)
            )
            .add(
                "thinkingLevel",
                string(message.thinking_level)
            )
        )

        if message.error_message != "": result.add(
            "errorMessage",
            string(message.error_message)
        )

        if message.provider_thinking_level != "": result.add(
            "providerThinkingLevel",
            string(message.provider_thinking_level)
        )

    if message.role == Role.ToolResult:
        (
            result
            .add(
                "toolCallId",
                string(message.tool_call_id)
            )
            .add(
                "toolName",
                string(message.tool_name)
            )
            .add(
                "isError",
                JsonValue.BoolValue(message.is_error)
            )
            .add("details", message.details)
        )

        if message.duration_ms.is_some(): result.add(
            "durationMs",
            numeric((message.duration_ms.unwrap()))
        )

    if message.usage.is_some(): result.add(
        "usage",
        usage_json(message.usage.unwrap())
    )

    return JsonValue.ObjectValue(result)

export fn proxy_payload(request: Request) -> JsonValue:
    let options = Map[String, JsonValue]()

    for name in [
        "temperature",
        "samplingParams",
        "maxTokens",
        "cacheRetention",
        "sessionId",
        "headers",
        "metadata",
        "transport",
        "thinkingBudgets",
        "maxRetryDelayMs"
    ]:
        let value = field(request.options, name)

        if value.is_some(): options.add(
            name,
            value.unwrap()
        )

    if request.thinking_level != "off": options.add(
        "reasoning",
        string(request.thinking_level)
    )

    let context = JsonValue.ObjectValue(
        {
            "messages": JsonValue.ArrayValue(
                (
                    request
                    .context
                    .messages
                    .map(
                        fn(message: Message) -> JsonValue: message_json(
                            message
                        )
                    )
                )
            )
        }
    )
    return JsonValue.ObjectValue(
        {
            "model": request.model_descriptor,
            "context": context,
            "options": JsonValue.ObjectValue(options)
        }
    )

export type ProxyState:
    message: Message = Message(Role.Assistant)
    fragments: Map[Int, String] = Map[Int, String]()
    terminal: Bool = false

fn index(event: JsonValue) -> Result[Int, Error]:
    let value = text(field(event, "contentIndex").unwrap_or(JsonValue.Null)).parse_int()
    if value.is_none() or value.unwrap() < 0: return error(
        AgentError.InvalidState("Proxy event has an invalid content index")
    )

    return ok(value.unwrap())

fn set_block(state: ProxyState, index: Int, block: Content) -> Result[Unit, Error]:
    if index > state.message.content.length(): return error(
        AgentError.InvalidState("Proxy event skipped a content index")
    )

    if index == state.message.content.length(): state.message.content.append(block)
    else: state.message.content.set(index, block)

    return ok(unit)

fn get_block(state: ProxyState, index: Int) -> Result[Content, Error]:
    let block = state.message.content[index]
    if block.is_none(): return error(
        AgentError.InvalidState("Proxy event refers to missing content")
    )

    return ok(block.unwrap())

fn usage(value: JsonValue) -> Usage:
    return Usage(
        input: (
            text(field(value, "input").unwrap_or(JsonValue.Null))
            .parse_int()
            .unwrap_or(0)
        ),
        output: (
            text(field(value, "output").unwrap_or(JsonValue.Null))
            .parse_int()
            .unwrap_or(0)
        ),
        cache_read: (
            text(field(value, "cacheRead").unwrap_or(JsonValue.Null))
            .parse_int()
            .unwrap_or(0)
        ),
        cache_write: (
            text(field(value, "cacheWrite").unwrap_or(JsonValue.Null))
            .parse_int()
            .unwrap_or(0)
        ),
        total_tokens: (
            text(field(value, "totalTokens").unwrap_or(JsonValue.Null))
            .parse_int()
            .unwrap_or(0)
        ),
        cost: field(value, "cost").unwrap_or(JsonValue.Null)
    )

fn partial_json(fragment: String) -> JsonValue:
    if parse(fragment).is_ok(): return parse(fragment).unwrap()

    let closers: List[String] = []
    var quoted = false
    var escaped = false

    for char in fragment.chars():
        if quoted:
            if escaped: escaped = false
            else if char == "\\": escaped = true
            else if char == "\"": quoted = false
        else if char == "\"": quoted = true
        else if char == "\{": closers.append("\}")
        else if char == "[": closers.append("]")
        else if char == "\}" or char == "]":
            let _closer = closers.pop()

    var candidate = fragment.trim_end()

    if escaped: candidate = candidate.slice(0, candidate.scalar_length() - 1).unwrap()

    if quoted: candidate = candidate + "\""

    if candidate.ends_with(":"): candidate = candidate + "null"

    if candidate.ends_with(","): candidate = (
        candidate
        .slice(0, (candidate.scalar_length() - 1))
        .unwrap()
    )

    candidate = candidate + closers.reversed().join("")
    return parse(candidate).unwrap_or(
        JsonValue.ObjectValue(Map[String, JsonValue]())
    )

export fn process_proxy_event(
    state: ProxyState,
    event: JsonValue
) -> Result[Unit, Error]:
    if state.terminal: return error(
        AgentError.InvalidState("Proxy event arrived after terminal event")
    )

    let kind = text(field(event, "type").unwrap_or(JsonValue.Null))
    if kind == "start": return ok(unit)

    if kind == "done" or kind == "error":
        let reason = text(field(event, "reason").unwrap_or(JsonValue.Null))
        if (
            kind == "done"
            and reason != "stop"
            and reason != "length"
            and reason != "toolUse"
        ): return error(AgentError.InvalidState("Invalid proxy completion reason"))
        if (
            kind == "error"
            and reason != "error"
            and reason != "aborted"
        ): return error(AgentError.InvalidState("Invalid proxy error reason"))

        var stop = StopReason.Stop

        if reason == "toolUse": stop = StopReason.ToolUse
        else if reason == "length": stop = StopReason.Length
        else if reason == "aborted": stop = StopReason.Aborted
        else if reason == "error": stop = StopReason.Failed
        else if reason != "stop": return error(
            AgentError.InvalidState("Proxy returned an unknown stop reason")
        )

        state.message.stop_reason = stop
        state.message.error_message = text(
            field(event, "errorMessage").unwrap_or(JsonValue.Null)
        )
        state.message.provider_thinking_level = text(
            field(event, "providerThinkingLevel").unwrap_or(JsonValue.Null)
        )
        state.message.usage = some(
            usage(field(event, "usage").unwrap_or(JsonValue.Null))
        )
        state.terminal = true
        return ok(unit)

    let position = try index(event)
    if kind == "text_start": return set_block(
        state,
        position,
        Content.Text("")
    )
    if kind == "thinking_start": return set_block(
        state,
        position,
        Content.Thinking("")
    )

    if kind == "toolcall_start":
        state.fragments.add(position, "")
        return set_block(
            state,
            position,
            Content.ToolCall(
                text(field(event, "id").unwrap_or(JsonValue.Null)),
                text(
                    field(event, "toolName").unwrap_or(
                        JsonValue.Null
                    )
                ),
                JsonValue.ObjectValue(Map[String, JsonValue]())
            )
        )

    let block = try get_block(state, position)

    if kind == "text_delta" or kind == "thinking_delta":
        let delta = text(field(event, "delta").unwrap_or(JsonValue.Null))
        return append_delta(
            state,
            position,
            block,
            kind,
            delta
        )

    if kind == "text_end" or kind == "thinking_end":
        let signature = field(event, "contentSignature")

        if signature.is_some(): (
            state
            .message
            .content_signatures
            .add(
                position,
                text(signature.unwrap())
            )
        )

        return check_end(block, kind)

    if kind == "toolcall_delta":
        let raw = (
            state.fragments.get_or(position, "")
            + text(field(event, "delta").unwrap_or(JsonValue.Null))
        )
        state.fragments.add(position, raw)

        let updated = match block:
            ToolCall(id, name, _): Content.ToolCall(
                id,
                name,
                partial_json(raw)
            )
            _: return error(
                AgentError.InvalidState(
                    "Proxy tool delta refers to another content type"
                )
            )

        return set_block(state, position, updated)

    if kind == "toolcall_end":
        let call = field(event, "toolCall").unwrap_or(JsonValue.Null)
        state.fragments.remove(position)
        return set_block(
            state,
            position,
            Content.ToolCall(
                text(field(call, "id").unwrap_or(JsonValue.Null)),
                text(field(call, "name").unwrap_or(JsonValue.Null)),
                field(call, "arguments").unwrap_or(JsonValue.Null)
            )
        )

    return error(AgentError.InvalidState("Unknown proxy event {kind}"))

fn append_delta(
    state: ProxyState,
    position: Int,
    block: Content,
    kind: String,
    delta: String
) -> Result[Unit, Error]:
    match block:
        Text(value):
            if kind != "text_delta": return error(
                AgentError.InvalidState("Proxy delta type mismatch")
            )

            return set_block(
                state,
                position,
                Content.Text(value + delta)
            )
        Thinking(value):
            if kind != "thinking_delta": return error(
                AgentError.InvalidState("Proxy delta type mismatch")
            )

            return set_block(
                state,
                position,
                Content.Thinking(value + delta)
            )
        _: return error(AgentError.InvalidState("Proxy delta type mismatch"))

fn check_end(block: Content, kind: String) -> Result[Unit, Error]:
    match block:
        Text(_):
            if kind == "text_end": return ok(unit)
        Thinking(_):
            if kind == "thinking_end": return ok(unit)
        _: unit

    return error(AgentError.InvalidState("Proxy end type mismatch"))

export fn read_proxy_stream(
    input: ReadStream,
    request: Request,
    control: Synchronized[Control],
    update: fn(message: Message) -> Unit,
    max_event_bytes: Optional[Int] = none
) -> Result[Message, Error]:
    let state = ProxyState(
        message: Message(
            Role.Assistant,
            model: request.model,
            provider: text(
                field(request.model_descriptor, "provider").unwrap_or(
                    JsonValue.Null
                )
            ),
            api: text(
                field(request.model_descriptor, "api").unwrap_or(
                    JsonValue.Null
                )
            )
        )
    )

    while true:
        if is_aborted(control): return error(
            AgentError.InvalidState("Operation aborted")
        )

        let line = try read_line(input, max_event_bytes)
        if line.is_none(): break
        if not line.unwrap().starts_with("data: "): continue

        let raw = line.unwrap().slice(
            6,
            line.unwrap().scalar_length()
        ).unwrap().trim()
        if raw == "": continue

        let event = try parse(raw)
        let _processed = try process_proxy_event(state, event)

        if request.provider_event.is_some(): request.provider_event.unwrap()(event)

        if state.terminal: return ok(state.message)
        if text(field(event, "type").unwrap_or(JsonValue.Null)) == "start": continue

        let snapshot = state.message.clone()
        snapshot.content = state.message.content.clone()
        snapshot.content_signatures = state.message.content_signatures.clone()
        update(snapshot)

    return error(AgentError.InvalidState("Proxy stream ended without a terminal event"))

fn proxy_http_error(
    reader: ReadStream,
    status: Int,
    max_bytes: Optional[Int]
) -> Result[Message, Error]:
    let body = read_all(reader, max_bytes)

    if body.is_ok() and body.unwrap().to_text().is_some():
        let value = parse(body.unwrap().to_text().unwrap())

        if value.is_ok():
            let message = field(
                value.unwrap(),
                "error"
            )
            if message.is_some() and text(message.unwrap()) != "": return error(
                AgentError.InvalidState(
                    "Proxy error: {text(message.unwrap())}"
                )
            )

    return error(AgentError.InvalidState("Proxy HTTP error {status}"))

export fn stream_proxy(
    options: ProxyOptions,
    request: Request,
    control: Synchronized[Control],
    update: fn(message: Message) -> Unit
) -> Result[Message, Error]:
    if is_aborted(control): return error(AgentError.InvalidState("Operation aborted"))

    with client = try options.make_client():
        with tasks = TaskGroup():
            let _watch = tasks.start(
                fn() -> Unit:
                    while true:
                        if is_aborted(control):
                            client.close()
                            return

                        sleep(duration(1000000))
            )
            let outgoing = headers()
            let _content_type = try outgoing.append(
                "Content-Type",
                "application/json".to_bytes()
            )
            let _authorization = try outgoing.append(
                "Authorization",
                "Bearer {options.auth_token}".to_bytes()
            )
            var payload = proxy_payload(request)

            if request.on_payload.is_some(): payload = (
                request
                .on_payload
                .unwrap()(payload)
            )

            let bytes = (try stringify(payload)).to_bytes()

            with body = try client.request(
                HttpMethod.Post,
                "{options.url.trim_end()}/api/stream",
                outgoing,
                bytes,
                max_response_bytes: options.max_response_bytes,
                timeout: options.timeout
            ):
                let status = body.metadata().status

                if request.on_response.is_some(): (
                    request
                    .on_response
                    .unwrap()(
                        JsonValue.ObjectValue(
                            {"status": numeric(status)}
                        )
                    )
                )

                let reader = ReadStream(BodyReader(body))
                if status < 200 or status >= 300: return proxy_http_error(
                    reader,
                    status,
                    options.max_response_bytes
                )

                return read_proxy_stream(
                    reader,
                    request,
                    control,
                    update,
                    options.max_event_bytes
                )

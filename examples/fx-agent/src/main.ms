import arguments from "@std/cli.ms"
import Bytes from "@std/bytes.ms"
import filesystem from "@std/fs.ms"
import {headers, HttpClientOptions, HttpMethod} from "@std/http.ms"
import {stdin, stdout, stderr, read_line} from "@std/io.ms"
import {parse, stringify, JsonValue} from "@std/json.ms"
import network from "@std/net.ms"
import commands from "@std/process.ms"
import system from "@std/system.ms"

type AgentError:
    message: String

impl Error for AgentError:
    fn message() -> String:
        return self.message

type Config:
    endpoint: String
    api_key: String
    model: String
    permission: String
    max_steps: Int
    session_path: String

type ToolCall:
    id: String
    name: String
    arguments: String

type ModelReply:
    content: String
    calls: List[ToolCall]
    raw_message: JsonValue

fn failure(message: String) -> Result[Unit, Error]:
    return error(AgentError(message))

fn string_value(value: JsonValue, field: String) -> Result[String, Error]:
    match value:
        JsonValue.StringValue(found): return ok(found)
        _: return error(AgentError("JSON field is not text: {field}"))

fn text(value: JsonValue, field: String) -> Result[String, Error]:
    match value:
        JsonValue.ObjectValue(fields):
            let item = fields.get(field)
            if item.is_none:
                return error(AgentError("missing JSON field: {field}"))

            return string_value(item.unwrap(), field)
        _:
            return error(AgentError("expected a JSON object"))

fn member(value: JsonValue, field: String) -> Result[JsonValue, Error]:
    match value:
        JsonValue.ObjectValue(fields):
            let item = fields.get(field)
            if item.is_none:
                return error(AgentError("missing JSON field: {field}"))

            return ok(item.unwrap())
        _:
            return error(AgentError("expected a JSON object"))

fn array(value: JsonValue, field: String) -> Result[List[JsonValue], Error]:
    let item = try member(value, field)

    match item:
        JsonValue.ArrayValue(values): return ok(values)
        _: return error(AgentError("JSON field is not an array: {field}"))

fn object(entries: Map[String, JsonValue]) -> JsonValue:
    return JsonValue.ObjectValue(entries)

fn message(role: String, content: String) -> JsonValue:
    return object(
        (
            Map[String, JsonValue]()
            .add("role", JsonValue.StringValue(role))
            .add("content", JsonValue.StringValue(content))
        )
    )

fn tool_message(call: ToolCall, output: String) -> JsonValue:
    return object(
        (
            Map[String, JsonValue]()
            .add("role", JsonValue.StringValue("tool"))
            .add("tool_call_id", JsonValue.StringValue(call.id))
            .add("content", JsonValue.StringValue(output))
        )
    )

fn optional_content(value: JsonValue) -> Result[String, Error]:
    match value:
        JsonValue.ObjectValue(fields):
            let content = fields.get("content")
            if content.is_none: return ok("")

            return nullable_content(content.unwrap())
        _: return error(AgentError("model message was not an object"))

fn nullable_content(value: JsonValue) -> Result[String, Error]:
    match value:
        JsonValue.StringValue(found): return ok(found)
        _: return ok("")

fn tool_calls(value: JsonValue) -> Result[List[ToolCall], Error]:
    let calls: List[ToolCall] = []
    let raw = try member(value, "tool_calls")

    match raw:
        JsonValue.ArrayValue(values):
            for item in values:
                let function = try member(item, "function")
                calls.append(
                    ToolCall(
                        id: try text(item, "id"),
                        name: try text(function, "name"),
                        arguments: try text(
                            function,
                            "arguments"
                        )
                    )
                )

            return ok(calls)
        _: return error(AgentError("tool_calls was not an array"))

fn optional_tool_calls(value: JsonValue) -> Result[List[ToolCall], Error]:
    match value:
        JsonValue.ObjectValue(fields):
            if not fields.contains("tool_calls"): return ok([])

            return tool_calls(value)
        _: return error(AgentError("model message was not an object"))

fn function_tool(
    name: String,
    description: String,
    properties: JsonValue,
    required: List[JsonValue]
) -> JsonValue:
    let parameters = object(
        (
            Map[String, JsonValue]()
            .add("type", JsonValue.StringValue("object"))
            .add("properties", properties)
            .add("required", JsonValue.ArrayValue(required))
            .add("additionalProperties", JsonValue.BoolValue(false))
        )
    )
    let function = object(
        (
            Map[String, JsonValue]()
            .add("name", JsonValue.StringValue(name))
            .add("description", JsonValue.StringValue(description))
            .add("parameters", parameters)
        )
    )
    return object(
        (
            Map[String, JsonValue]()
            .add("type", JsonValue.StringValue("function"))
            .add("function", function)
        )
    )

fn string_property(description: String) -> JsonValue:
    return object(
        (
            Map[String, JsonValue]()
            .add("type", JsonValue.StringValue("string"))
            .add("description", JsonValue.StringValue(description))
        )
    )

fn tools() -> List[JsonValue]:
    return [
        function_tool(
            "read_file",
            "Read a UTF-8 file in the current workspace.",
            object(
                Map[String, JsonValue]().add(
                    "path",
                    string_property("Workspace-relative file path")
                )
            ),
            [JsonValue.StringValue("path")]
        ),
        function_tool(
            "write_file",
            "Create or replace a UTF-8 file after permission review.",
            object(
                (
                    Map[String, JsonValue]()
                    .add(
                        "path",
                        string_property(
                            "Workspace-relative file path"
                        )
                    )
                    .add(
                        "content",
                        string_property(
                            "Complete replacement contents"
                        )
                    )
                )
            ),
            [
                JsonValue.StringValue("path"),
                JsonValue.StringValue("content")
            ]
        ),
        function_tool(
            "shell",
            "Run a command through the user's shell after permission review.",
            object(
                Map[String, JsonValue]().add(
                    "command",
                    string_property("Shell command")
                )
            ),
            [JsonValue.StringValue("command")]
        ),
        function_tool(
            "list_files",
            "List files below a workspace-relative directory.",
            object(
                Map[String, JsonValue]().add(
                    "path",
                    string_property(
                        "Directory path, or . for the workspace"
                    )
                )
            ),
            [JsonValue.StringValue("path")]
        ),
        function_tool(
            "search",
            "Search workspace file contents with a regular expression.",
            object(
                (
                    Map[String, JsonValue]()
                    .add(
                        "query",
                        string_property("Regular expression")
                    )
                    .add(
                        "path",
                        string_property(
                            "File or directory to search"
                        )
                    )
                )
            ),
            [JsonValue.StringValue("query"), JsonValue.StringValue("path")]
        ),
        function_tool(
            "web_fetch",
            "Fetch a public HTTP or HTTPS URL as UTF-8 text.",
            object(
                Map[String, JsonValue]().add(
                    "url",
                    string_property("URL to fetch")
                )
            ),
            [JsonValue.StringValue("url")]
        ),
        function_tool(
            "delegate",
            "Ask a focused subagent to investigate a task and return its answer.",
            object(
                Map[String, JsonValue]().add(
                    "prompt",
                    string_property("Focused subtask")
                )
            ),
            [JsonValue.StringValue("prompt")]
        )
    ]

fn load_config() -> Result[Config, Error]:
    let host = system()
    let key = host.environment("FX_API_KEY")
    if key.is_none:
        return error(AgentError("FX_API_KEY is required"))

    let endpoint = (
        host
        .environment("FX_BASE_URL")
        .unwrap_or("https://api.openai.com/v1/chat/completions")
    )
    let model = host.environment("FX_MODEL").unwrap_or("gpt-4.1-mini")
    let permission = host.environment("FX_PERMISSION").unwrap_or("ask")
    if (permission != "ask" and permission != "auto" and permission != "full-access"):
        return error(AgentError("FX_PERMISSION must be ask, auto, or full-access"))

    let steps_text = host.environment("FX_MAX_STEPS").unwrap_or("32")
    let steps = steps_text.parse_int()
    if steps.is_none or steps.unwrap() < 1:
        return error(AgentError("FX_MAX_STEPS must be a positive integer"))

    return ok(
        Config(
            endpoint: endpoint,
            api_key: key.unwrap(),
            model: model,
            permission: permission,
            max_steps: steps.unwrap(),
            session_path: (
                host
                .environment("FX_SESSION")
                .unwrap_or(".fx-manuscript-session.jsonl")
            )
        )
    )

fn read_instructions() -> String:
    match filesystem().read_file("AGENTS.md", max_bytes: 262144):
        ok(data): return data.to_text().unwrap_or("")
        error(_): return ""

fn prompt_from_args() -> Result[String, Error]:
    let supplied = arguments()
    if supplied.length > 0:
        return ok(supplied.join(" "))

    try stdout().write("fx> ".to_bytes())
    let line = try read_line(stdin(), max_bytes: 1048576)
    if line.is_none: return error(AgentError("no prompt supplied"))

    return ok(line.unwrap())

fn approve(config: Config, action: String, mutating: Bool) -> Result[Bool, Error]:
    if config.permission == "full-access": return ok(true)
    if config.permission == "auto" and not mutating: return ok(true)

    try stderr().write("Allow {action}? [y/N] ".to_bytes())
    let answer = try read_line(stdin(), max_bytes: 32)
    if answer.is_none: return ok(false)

    let normalized = answer.unwrap().trim().lower()
    return ok(normalized == "y" or normalized == "yes")

fn execute(call: ToolCall, config: Config) -> Result[String, Error]:
    let arguments_value = try parse(call.arguments)

    if call.name == "read_file":
        let path = try text(arguments_value, "path")
        if not (try approve(config, "read {path}", false)):
            return ok("permission denied")

        let data = try filesystem().read_file(path, max_bytes: 1048576)
        let decoded = data.to_text()
        if decoded.is_none: return ok("file is not valid UTF-8")

        return ok(decoded.unwrap())

    if call.name == "write_file":
        let path = try text(arguments_value, "path")
        let content = try text(arguments_value, "content")
        if not (try approve(config, "replace {path}", true)):
            return ok("permission denied")

        try filesystem().write_file(path, content.to_bytes(), replace: true)
        return ok("wrote {content.to_bytes().length} bytes to {path}")

    if call.name == "shell":
        let command = try text(arguments_value, "command")
        if not (try approve(config, "run `{command}`", true)):
            return ok("permission denied")

        let shell = system().environment("SHELL").unwrap_or("/bin/sh")
        let output = try commands().run(
            shell,
            ["-lc", command],
            max_output_bytes: 1048576
        )
        let out = output.stdout.to_text().unwrap_or("<stdout was not UTF-8>")
        let err = output.stderr.to_text().unwrap_or("<stderr was not UTF-8>")
        return ok("exit {output.exit_code}\nstdout:\n{out}\nstderr:\n{err}")

    if call.name == "list_files":
        let path = try text(arguments_value, "path")
        if not (try approve(config, "list {path}", false)):
            return ok("permission denied")

        let entries = try filesystem().list(path, max_entries: 10000)
        var names: List[String] = []

        for entry in entries:
            var suffix = ""

            if entry.directory: suffix = "/"

            names.append("{entry.name}{suffix}")

        return ok(names.join("\n"))

    if call.name == "search":
        let query = try text(arguments_value, "query")
        let path = try text(arguments_value, "path")
        if not (try approve(config, "search {path} for {query}", false)):
            return ok("permission denied")

        let output = try commands().run(
            "rg",
            ["--line-number", "--color", "never", "--", query, path],
            max_output_bytes: 1048576
        )
        let out = output.stdout.to_text().unwrap_or("<search output was not UTF-8>")
        let err = output.stderr.to_text().unwrap_or("<search error was not UTF-8>")
        return ok("exit {output.exit_code}\n{out}{err}")

    if call.name == "web_fetch":
        let url = try text(arguments_value, "url")
        if not (try approve(config, "fetch {url}", false)):
            return ok("permission denied")

        with client = try network().http_client(HttpClientOptions(decompress: true)):
            with response = try client.request(
                HttpMethod.Get,
                url,
                headers(),
                max_response_bytes: 2097152
            ):
                let data = try response.read(max_bytes: 2097152)
                if data.is_none: return ok("")

                return ok(data.unwrap().to_text().unwrap_or("<response was not UTF-8>"))

    if call.name == "delegate":
        let prompt = try text(arguments_value, "prompt")
        let child_messages = [
            message(
                "system",
                "You are a focused coding subagent. Investigate the supplied task and return concise evidence. Do not call tools."
            ),
            message("user", prompt)
        ]
        let reply = try request(config, child_messages)
        if not reply.calls.is_empty:
            return ok(
                "subagent requested tools; narrow the task or investigate directly"
            )

        return ok(reply.content)

    return ok("unknown tool: {call.name}")

fn request(config: Config, messages: List[JsonValue]) -> Result[ModelReply, Error]:
    let body = object(
        (
            Map[String, JsonValue]()
            .add("model", JsonValue.StringValue(config.model))
            .add("messages", JsonValue.ArrayValue(messages))
            .add("tools", JsonValue.ArrayValue(tools()))
            .add("tool_choice", JsonValue.StringValue("auto"))
        )
    )
    let encoded = try stringify(body, max_bytes: 8388608)
    let request_headers = headers()
    let auth = try request_headers.append(
        "Authorization",
        "Bearer {config.api_key}".to_bytes()
    )
    let content_type = try request_headers.append(
        "Content-Type",
        "application/json".to_bytes()
    )

    with client = try network().http_client(HttpClientOptions()):
        with response = try client.request(
            HttpMethod.Post,
            config.endpoint,
            request_headers,
            encoded.to_bytes(),
            max_response_bytes: 16777216
        ):
            let response_body = try response.read(max_bytes: 16777216)
            if response_body.is_none: return error(
                AgentError("model returned an empty body")
            )

            let response_text = response_body.unwrap().to_text()
            if response_text.is_none: return error(
                AgentError("model response was not UTF-8")
            )
            if response.metadata.status < 200 or response.metadata.status >= 300:
                return error(
                    AgentError(
                        "model HTTP {response.metadata.status}: {response_text.unwrap()}"
                    )
                )

            let root = try parse(response_text.unwrap())
            let choices = try array(root, "choices")
            if choices.is_empty: return error(
                AgentError("model response had no choices")
            )

            let response_message = try member(choices.first.unwrap(), "message")
            let content = try optional_content(response_message)
            let calls = try optional_tool_calls(response_message)

            return ok(ModelReply(content, calls, response_message))

fn save_session(config: Config, messages: List[JsonValue]) -> Result[Unit, Error]:
    let encoded = try stringify(JsonValue.ArrayValue(messages), max_bytes: 16777216)
    try filesystem().write_file(config.session_path, encoded.to_bytes(), replace: true)
    return ok(unit)

fn decoded_session(value: JsonValue) -> List[JsonValue]:
    match value:
        JsonValue.ArrayValue(values): return values
        _: return []

fn parsed_session(text: String) -> List[JsonValue]:
    match parse(text):
        ok(value): return decoded_session(value)
        error(_): return []

fn session_bytes(data: Bytes) -> List[JsonValue]:
    let decoded = data.to_text()
    if decoded.is_none: return []

    return parsed_session(decoded.unwrap())

fn load_session(config: Config) -> List[JsonValue]:
    if system().environment("FX_CONTINUE").unwrap_or("") != "1": return []

    match filesystem().read_file(config.session_path, max_bytes: 16777216):
        ok(data): return session_bytes(data)
        error(_): return []

fn run() -> Result[Unit, Error]:
    let config = try load_config()
    let user_prompt = try prompt_from_args()
    let instructions = "You are a concise coding agent. Inspect before editing, use tools to complete the request, and report checks run. Workspace instructions follow:\n{read_instructions()}"
    let messages = load_session(config)

    if messages.is_empty: messages.append(message("system", instructions))

    messages.append(message("user", user_prompt))
    var step = 0

    while step < config.max_steps:
        let reply = try request(config, messages)
        messages.append(reply.raw_message)

        if not reply.content.is_empty:
            try stdout().write("{reply.content}\n".to_bytes())

        if reply.calls.is_empty:
            return save_session(config, messages)

        for call in reply.calls:
            try stderr().write("tool {call.name}\n".to_bytes())
            let result = try execute(call, config)
            messages.append(tool_message(call, result))

        try save_session(config, messages)
        step = step + 1

    return failure("agent exceeded FX_MAX_STEPS")

fn report_error(cause: Error) -> Int:
    match stderr().write("fx: {cause.message()}\n".to_bytes()):
        ok(_): return 1
        error(_): return 1

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(cause): return report_error(cause)

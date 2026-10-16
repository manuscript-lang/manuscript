import TextError from "@std/errors.ms"
# Native HTTP fixture exercised by tests/examples; no public provider is contacted.
import {
    create_agent,
    prompt_text,
    abort,
    active_signal,
    wait_for_idle
} from "./agent.ms"
import {
    Config,
    Request,
    Message,
    Control,
    StopReason,
    Event
} from "./types.ms"
import {ProxyOptions, stream_proxy} from "./proxy.ms"
import content_text from "./transcript.ms"
import {JsonValue} from "@std/json.ms"
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"
import Synchronized from "@std/sync.ms"
import {TaskGroup, yield_now} from "@std/tasks.ms"
import {duration, Duration} from "@std/time.ms"

fn run() -> Result[Unit, Error]:
    let args = arguments()
    if args.length != 2: return error(TextError.Text("expected URL and mode"))

    let url = args[0].unwrap()
    let mode = args[1].unwrap()
    let seen = Synchronized(false)
    let observed: List[JsonValue] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        var timeout: Optional[Duration] = none
        var max_event_bytes: Optional[Int] = none

        if mode == "timeout": timeout = some(duration(40000000))

        if mode == "limit": max_event_bytes = some(8)

        return stream_proxy(
            ProxyOptions(
                url,
                auth_token: "test",
                timeout: timeout,
                max_event_bytes: max_event_bytes
            ),
            request,
            control,
            update
        )
    let response = fn(response: JsonValue) -> Unit:
        with guard = seen.lock(): guard.set(true)
    let payload = fn(payload: JsonValue) -> JsonValue:
        let values = match payload:
            ObjectValue(values): values.clone()
            _: return payload

        values.add("marker", JsonValue.StringValue("native"))
        return JsonValue.ObjectValue(values)
    let provider_event = fn(event: JsonValue) -> Unit:
        observed.append(event)
    let config = Config(
        stream: model,
        emit: fn(event: Event) -> Unit: unit,
        model: "fixture",
        api_key: "never-forward",
        model_descriptor: JsonValue.ObjectValue(
            {
                "id": JsonValue.StringValue("fixture"),
                "api": JsonValue.StringValue("fixture-api"),
                "provider": JsonValue.StringValue("fixture-provider")
            }
        ),
        options: JsonValue.ObjectValue(
            {"sessionId": JsonValue.StringValue("session")}
        ),
        on_response: some(response),
        on_payload: some(payload),
        provider_event: some(provider_event)
    )
    let agent = create_agent(config)

    if mode == "abort":
        with tasks = TaskGroup():
            let task = tasks.start(
                fn() -> Result[List[Message], Error]: prompt_text(
                    agent,
                    "hello"
                )
            )

            while true:
                var ready = false

                with guard = seen.lock(): ready = guard.value

                if ready: break

                yield_now()

            abort(agent)
            wait_for_idle(agent)
            let outcome = try task.join()
            if outcome.is_ok or active_signal(agent).is_some: return error(
                TextError.Text("abort did not settle")
            )
            if agent.context.messages.last.unwrap().stop_reason != StopReason.Aborted: return error(
                TextError.Text("abort reason missing")
            )
    else:
        let outcome = prompt_text(agent, "hello")

        if mode == "normal":
            let _messages = try outcome
            let message = agent.context.messages.last.unwrap()
            if (
                content_text(message.content) != "héllo"
                or message.usage.unwrap().total_tokens != 3
            ): return error(TextError.Text("proxy content or usage lost"))
            if (
                message.content_signatures.get(0) != some("sig")
                or message.provider_thinking_level != "native-level"
            ): return error(TextError.Text("proxy metadata lost"))
            if observed.length != 5: return error(
                TextError.Text("provider events missing")
            )
        else:
            if outcome.is_ok: return error(
                TextError.Text("bad proxy response accepted")
            )
            if agent.is_streaming: return error(
                TextError.Text("failed proxy did not settle")
            )

    let _written = try stdout().write("proxy ok\n".to_bytes())
    return ok(unit)

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(cause):
            let _written = stdout().write("{cause.message()}\n".to_bytes())
            return 1

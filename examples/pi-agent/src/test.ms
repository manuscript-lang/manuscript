import yield_now from "@std/tasks.ms"
import {
    create_agent,
    prompt,
    continue_agent,
    steer,
    follow_up,
    abort,
    reset,
    is_aborted,
    run_tool_call,
    subscribe,
    run_agent_loop,
    run_agent_loop_continue
} from "./agent.ms"
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
    StopReason,
    ExecutionMode,
    QueueMode,
    Decision,
    Turn,
    Preflight,
    AgentError
} from "./types.ms"
import Synchronized from "@std/sync.ms"
import JsonValue from "@std/json.ms"
import panic from "@std/faults.ms"

fn ignore(event: Event) -> Unit: unit

fn valid(arguments: JsonValue) -> Result[JsonValue, Error]: ok(arguments)

fn invalid(arguments: JsonValue) -> Result[JsonValue, Error]: error(
    AgentError.InvalidState("invalid arguments")
)

fn echo(
    call: ToolCall,
    control: Synchronized[Control],
    update: fn(result: ToolResult) -> Unit
) -> Result[ToolResult, Error]:
    update(ToolResult([Content.Text("working")]))
    return ok(ToolResult([Content.Text(call.id)]))

fn failed(
    call: ToolCall,
    control: Synchronized[Control],
    update: fn(result: ToolResult) -> Unit
) -> Result[ToolResult, Error]:
    return error(AgentError.InvalidState("tool failed"))

fn complete(
    request: Request,
    control: Synchronized[Control],
    update: fn(message: Message) -> Unit
) -> Result[Message, Error]:
    return ok(Message(Role.Assistant, [Content.Text("done")]))

fn two_calls(
    request: Request,
    control: Synchronized[Control],
    update: fn(message: Message) -> Unit
) -> Result[Message, Error]:
    if request.context.messages.last().unwrap().role == Role.ToolResult:
        return complete(request, control, update)

    update(Message(Role.Assistant, [Content.Text("working")]))
    return ok(
        Message(
            Role.Assistant,
            [
                Content.ToolCall("a", "echo", JsonValue.Null),
                Content.ToolCall("b", "echo", JsonValue.Null)
            ],
            StopReason.ToolUse
        )
    )

fn user(text: String) -> Message: Message(Role.User, [Content.Text(text)])

fn tool() -> Tool: Tool(
    "echo",
    "echo",
    JsonValue.Null,
    valid,
    echo
)

fn check_batch(mode: ExecutionMode) -> Unit:
    let events: List[Event] = []
    let sink = fn(event: Event) -> Unit:
        events.append(event)
    let agent = create_agent(
        Config(stream: two_calls, emit: sink, tool_execution: mode),
        Context(tools: [tool()])
    )
    let result = prompt(agent, [user("go")])

    if result.is_error():
        panic("batch failed")

    let messages = result.unwrap()

    if (
        messages.length() != 5
        or messages[2].unwrap().tool_call_id != "a"
        or messages[3].unwrap().tool_call_id != "b"
    ):
        panic("results must follow assistant source order")

    if (
        agent.is_streaming
        or not agent.pending_tool_calls.is_empty()
        or agent.streaming_message.is_some()
    ):
        panic("agent did not settle")

    if events.first().unwrap() != Event.AgentStart:
        panic("missing start")

    match events.last().unwrap():
        AgentEnd(returned):
            if returned.length() != messages.length(): panic("end result changed")
        _: panic("missing end")

test "sequential tool loop":
    check_batch(ExecutionMode.Sequential)

test "parallel tool loop preserves transcript order":
    check_batch(ExecutionMode.Parallel)

test "unknown invalid and failed tools become error results":
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(tools: [tool()])
    )
    let update = fn(result: ToolResult) -> Unit: unit

    if not run_tool_call(
        agent,
        ToolCall("a", "missing", JsonValue.Null),
        update
    ).is_error:
        panic("unknown tool executed")

    agent.context.tools = [
        Tool(
            "echo",
            "echo",
            JsonValue.Null,
            invalid,
            echo
        )
    ]

    if not run_tool_call(
        agent,
        ToolCall("a", "echo", JsonValue.Null),
        update
    ).is_error:
        panic("invalid arguments executed")

    agent.context.tools = [
        Tool(
            "echo",
            "echo",
            JsonValue.Null,
            valid,
            failed
        )
    ]

    if not run_tool_call(
        agent,
        ToolCall("a", "echo", JsonValue.Null),
        update
    ).is_error:
        panic("tool error lost")

test "queues drain steering before follow ups":
    let seen: List[String] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        let message = request.context.messages.last().unwrap()

        match message.content.first().unwrap():
            Text(text): seen.append(text)
            _: panic("expected text")

        return ok(Message(Role.Assistant))
    let agent = create_agent(Config(stream: model, emit: ignore))
    steer(
        agent,
        user("steer one")
    )
    steer(
        agent,
        user("steer two")
    )
    follow_up(
        agent,
        user("follow")
    )

    if prompt(agent, [user("initial")]).is_error(): panic("queue run failed")

    if seen != ["steer one", "steer two", "follow"]: panic("queue order changed")

test "continuation and reset validate idle state":
    let agent = create_agent(Config(stream: complete, emit: ignore))

    if continue_agent(agent).is_ok(): panic("empty continuation accepted")

    agent.context.messages.append(user("retry"))
    let result = continue_agent(agent)

    if result.is_error() or result.unwrap().length() != 1: panic(
        "continuation replayed existing history"
    )

    if continue_agent(agent).is_ok(): panic("assistant continuation accepted")

    abort(agent)

    if not is_aborted(agent.control): panic("abort token was not set")

    if reset(agent).is_error() or not agent.context.messages.is_empty(): panic(
        "reset failed"
    )

    agent.is_streaming = true

    if prompt(agent, [user("busy")]).is_ok() or reset(agent).is_ok(): panic(
        "busy operation accepted"
    )

test "provider errors settle with complete lifecycle":
    let events: List[Event] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        return error(AgentError.InvalidState("provider failed"))
    let sink = fn(event: Event) -> Unit:
        events.append(event)
    let agent = create_agent(Config(stream: model, emit: sink))

    if prompt(agent, [user("go")]).is_ok(): panic("provider error lost")

    if agent.is_streaming or agent.error_message != "provider failed": panic(
        "failed state not settled"
    )

    if agent.context.messages.last().unwrap().stop_reason != StopReason.Failed: panic(
        "failed assistant missing"
    )

    match events.last().unwrap():
        AgentEnd(_): return
        _: panic("failed run did not end")

test "cooperative abort stops tool dispatch":
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        with guard = control.lock():
            guard.get().aborted = true

        return ok(
            Message(
                Role.Assistant,
                [Content.ToolCall("a", "echo", JsonValue.Null)],
                StopReason.ToolUse
            )
        )
    let agent = create_agent(
        Config(stream: model, emit: ignore),
        Context(tools: [tool()])
    )

    if prompt(agent, [user("go")]).is_ok(): panic("abort ignored")

    if not is_aborted(agent.control) or agent.context.messages.length() != 2: panic(
        "aborted response dispatched tools"
    )

test "length limited tool arguments never execute":
    let executed = Synchronized(0)
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        with guard = executed.lock():
            guard.set(guard.get() + 1)

        return ok(ToolResult())
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        if request.context.messages.last().unwrap().role == Role.ToolResult:
            return ok(Message(Role.Assistant))

        return ok(
            Message(
                Role.Assistant,
                [Content.ToolCall("a", "echo", JsonValue.Null)],
                StopReason.Length
            )
        )
    let agent = create_agent(
        Config(stream: model, emit: ignore),
        Context(
            tools: [
                Tool(
                    "echo",
                    "echo",
                    JsonValue.Null,
                    valid,
                    execute
                )
            ]
        )
    )

    if prompt(agent, [user("go")]).is_error(): panic("length recovery failed")

    with guard = executed.lock():
        if guard.get() != 0: panic("truncated arguments executed")

    if not agent.context.messages[2].unwrap().is_error: panic(
        "truncated call error missing"
    )

test "finish turn end leaves queued work untouched":
    let finish = fn(turn: Turn) -> Decision: Decision.End
    let agent = create_agent(
        Config(
            stream: complete,
            emit: ignore,
            finish_turn: some(finish)
        )
    )
    follow_up(
        agent,
        user("later")
    )

    if prompt(agent, [user("now")]).is_error(): panic("finish failed")

    with guard = agent.control.lock():
        if guard.get().follow_up.length() != 1: panic("end drained queued work")

test "blocking every tool terminates batch":
    let before = fn(call: ToolCall, context: Context) -> Result[Preflight, Error]:
        return ok(Preflight(blocked: true, terminate: true))
    let agent = create_agent(
        Config(
            stream: two_calls,
            emit: ignore,
            before_tool_call: some(before)
        ),
        Context(tools: [tool()])
    )
    let result = prompt(agent, [user("go")])

    if result.is_error() or result.unwrap().length() != 4: panic(
        "blocked batch requested another turn"
    )

test "parallel tools overlap and end in completion order":
    let started = Synchronized(0)
    let second_ended = Synchronized(false)
    let ended: List[String] = []
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        with guard = started.lock():
            guard.set(guard.get() + 1)

        while true:
            var ready = false

            with guard = started.lock():
                ready = guard.get() == 2

            if ready: break

            yield_now()

        if call.id == "a":
            while true:
                var ready = false

                with guard = second_ended.lock():
                    ready = guard.get()

                if ready: break

                yield_now()

        return ok(ToolResult([Content.Text(call.id)]))
    let sink = fn(event: Event) -> Unit:
        match event:
            ToolEnd(call, _):
                ended.append(call.id)

                if call.id == "b":
                    with guard = second_ended.lock():
                        guard.set(true)
            _: return
    let agent = create_agent(
        Config(stream: two_calls, emit: sink),
        Context(
            tools: [
                Tool(
                    "echo",
                    "echo",
                    JsonValue.Null,
                    valid,
                    execute
                )
            ]
        )
    )

    if prompt(agent, [user("go")]).is_error(): panic("parallel overlap failed")

    if ended != ["b", "a"]: panic("tool end events did not follow completion order")

    if agent.context.messages[2].unwrap().tool_call_id != "a": panic(
        "completion order leaked into transcript"
    )

test "preflight is ordered and after hook replaces result":
    let order: List[String] = []
    let before = fn(call: ToolCall, context: Context) -> Result[Preflight, Error]:
        order.append(call.id)
        return ok(Preflight())
    let after = fn(
        call: ToolCall,
        result: ToolResult,
        context: Context
    ) -> Result[ToolResult, Error]:
        return ok(ToolResult([Content.Text("replacement")], is_error: true))
    let agent = create_agent(
        Config(
            stream: two_calls,
            emit: ignore,
            before_tool_call: some(before),
            after_tool_call: some(after)
        ),
        Context(tools: [tool()])
    )

    if prompt(agent, [user("go")]).is_error(): panic("hook run failed")

    if order != ["a", "b"]: panic("preflight order changed")

    if not agent.context.messages[2].unwrap().is_error: panic(
        "after hook override lost"
    )

test "request transforms do not prune durable history":
    let requests: List[String] = []
    let counts: List[Int] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        requests.append(request.model)
        counts.append(request.context.messages.length())
        return ok(Message(Role.Assistant))
    let transform = fn(messages: List[Message]) -> Result[List[Message], Error]: ok(
        messages.take(1)
    )
    let prepare = fn(request: Request) -> Request:
        return Request(request.context, "changed", "high")
    let finish = fn(turn: Turn) -> Decision:
        if turn.context.messages.length() == 3: return Decision.Continue

        return Decision.End
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            transform_context: some(transform),
            prepare_request: some(prepare),
            finish_turn: some(finish)
        ),
        Context(messages: [Message(Role.System)])
    )

    if prompt(agent, [user("go")]).is_error(): panic("request preparation failed")

    if requests != ["changed", "changed"] or counts != [1, 1]: panic(
        "request transform or continuation lost"
    )

    if agent.context.messages.length() != 4: panic("transform changed durable history")

test "subscriptions settle before idle and can unsubscribe":
    let agent = create_agent(Config(stream: complete, emit: ignore))
    let endings: List[Bool] = []
    let listener = fn(event: Event) -> Unit:
        match event:
            AgentEnd(_): endings.append(agent.is_streaming)
            _: return
    let unsubscribe = subscribe(agent, listener)

    if prompt(agent, [user("one")]).is_error(): panic("subscribed run failed")

    unsubscribe()

    if prompt(agent, [user("two")]).is_error(): panic("unsubscribed run failed")

    if endings != [true]: panic("listener settlement or unsubscribe failed")

test "all queue mode injects every message in a single turn":
    let agent = create_agent(
        Config(
            stream: complete,
            emit: ignore,
            steering_mode: QueueMode.All,
            follow_up_mode: QueueMode.All
        )
    )
    steer(
        agent,
        user("one")
    )
    steer(
        agent,
        user("two")
    )
    follow_up(
        agent,
        user("three")
    )
    follow_up(
        agent,
        user("four")
    )
    let result = prompt(agent, [user("start")])

    if result.is_error() or result.unwrap().length() != 7: panic(
        "all mode did not drain batches"
    )

test "low level entrypoints copy transcript and return only new messages":
    let context = Context(messages: [user("existing")])
    let config = Config(stream: complete, emit: ignore)
    let result = run_agent_loop([user("new")], context, config)

    if result.is_error() or result.unwrap().length() != 2: panic(
        "low level prompt failed"
    )

    if context.messages.length() != 1: panic("low level loop mutated caller transcript")

    let continued = run_agent_loop_continue(context, config)

    if continued.is_error() or continued.unwrap().length() != 1: panic(
        "low level continuation failed"
    )

test "next turn preparation runs only for scheduled continuation":
    let prepared: List[Int] = []
    let models: List[String] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        models.append(request.model)
        return ok(Message(Role.Assistant))
    let finish = fn(turn: Turn) -> Decision:
        if turn.new_messages.length() == 2: return Decision.Continue

        return Decision.End
    let next = fn(turn: Turn) -> Request:
        prepared.append(turn.new_messages.length())
        return Request(turn.context, "next", "high")
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            model: "first",
            finish_turn: some(finish),
            prepare_next_turn: some(next)
        )
    )

    if prompt(agent, [user("go")]).is_error(): panic("next turn failed")

    if models != ["first", "next"] or prepared != [2]: panic(
        "next preparation scheduling changed"
    )

    if agent.config.model != "next" or agent.config.thinking_level != "high": panic(
        "request update was not retained"
    )

test "transform errors produce a failed assistant and turn end":
    let events: List[Event] = []
    let sink = fn(event: Event) -> Unit:
        events.append(event)
    let transform = fn(messages: List[Message]) -> Result[List[Message], Error]:
        return error(AgentError.InvalidState("transform failed"))
    let agent = create_agent(
        Config(
            stream: complete,
            emit: sink,
            transform_context: some(transform)
        )
    )

    if prompt(agent, [user("go")]).is_ok(): panic("transform failure lost")

    if agent.context.messages.last().unwrap().stop_reason != StopReason.Failed: panic(
        "failed assistant missing"
    )

    match events[events.length() - 2].unwrap():
        TurnEnd(_, _): return
        _: panic("transform failure skipped turn end")

test "settled providers and tools ignore late partial updates":
    let partials: List[Event] = []
    let saved_model: List[fn(message: Message) -> Unit] = []
    let saved_tool: List[fn(result: ToolResult) -> Unit] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        saved_model.append(update)
        return ok(Message(Role.Assistant))
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        saved_tool.append(update)
        return ok(ToolResult())
    let sink = fn(event: Event) -> Unit:
        match event:
            MessageUpdate(_): partials.append(event)
            ToolUpdate(_, _): partials.append(event)
            _: return
    let agent = create_agent(
        Config(stream: model, emit: sink),
        Context(
            tools: [
                Tool(
                    "echo",
                    "echo",
                    JsonValue.Null,
                    valid,
                    execute
                )
            ]
        )
    )

    if prompt(agent, [user("go")]).is_error(): panic("provider failed")

    saved_model.first().unwrap()(Message(Role.Assistant, [Content.Text("late")]))
    let update = fn(result: ToolResult) -> Unit:
        partials.append(
            Event.ToolUpdate(
                ToolCall("a", "echo", JsonValue.Null),
                result
            )
        )
    let _result = run_tool_call(
        agent,
        ToolCall("a", "echo", JsonValue.Null),
        update
    )
    saved_tool.first().unwrap()(ToolResult([Content.Text("late")]))

    if not partials.is_empty() or agent.streaming_message.is_some(): panic(
        "late update was accepted"
    )

test "argument normalization preserves raw call and transcript":
    let validate = fn(arguments: JsonValue) -> Result[JsonValue, Error]:
        return ok(JsonValue.StringValue("normalized"))
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        if call.arguments != JsonValue.StringValue("normalized"): panic(
            "executor missed normalized arguments"
        )

        return ok(ToolResult())
    let before = fn(call: ToolCall, context: Context) -> Result[Preflight, Error]:
        if call.arguments != JsonValue.StringValue("normalized"): panic(
            "hook missed normalized arguments"
        )

        return ok(Preflight())
    let calls: List[ToolCall] = []
    let sink = fn(event: Event) -> Unit:
        match event:
            ToolStart(call): calls.append(call)
            _: return
    let agent = create_agent(
        Config(
            stream: two_calls,
            emit: sink,
            before_tool_call: some(before)
        ),
        Context(
            tools: [
                Tool(
                    "echo",
                    "echo",
                    JsonValue.Null,
                    validate,
                    execute
                )
            ]
        )
    )

    if prompt(agent, [user("go")]).is_error(): panic("normalized run failed")

    if not calls.every(
        fn(call: ToolCall) -> Bool: call.arguments == JsonValue.Null
    ): panic("normalization changed raw events")

    let raw = ToolCall("c", "echo", JsonValue.Null)
    let update = fn(result: ToolResult) -> Unit: unit
    let result = run_tool_call(agent, raw, update)

    if result.is_error or raw.arguments != JsonValue.Null: panic(
        "normalization mutated caller data"
    )

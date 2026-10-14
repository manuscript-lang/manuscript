import {ProxyState, process_proxy_event, proxy_payload, message_json} from "./proxy.ms"
import {current_tools, collapse_system_messages} from "./transcript.ms"
import {field, validate_arguments, validate_output} from "./schema.ms"
import TaskGroup from "@std/tasks.ms"
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
    run_agent_loop_continue,
    peek_queued_messages,
    clear_steering_queue,
    clear_follow_up_queue,
    clear_all_queues,
    has_queued_messages,
    set_tools,
    get_system_prompt,
    prompt_text,
    prompt_message,
    replace_messages,
    append_message,
    set_default_stream_fn,
    run_tool_call_outcome,
    wait_for_idle,
    active_signal
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
    AgentError,
    ToolDeclaration,
    ToolResultPatch,
    Usage,
    StreamRuntime
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

    match events.first().unwrap():
        AgentStart: unit
        _: panic("missing start")

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

    if is_aborted(agent.control): panic("idle abort should be a no-op")

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

    if (
        not is_aborted(agent.control)
        or agent.context.messages.filter(
            fn(message: Message) -> Bool: (message.role != Role.System)
        ).length() != 2
    ): panic(
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

    if (
        not agent
        .context
        .messages
        .filter(
            fn(message: Message) -> Bool: (message.role == Role.ToolResult)
        )
        .first()
        .unwrap()
        .is_error
    ): panic(
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

    if (
        agent.context.messages.filter(
            fn(message: Message) -> Bool: (message.role == Role.ToolResult)
        ).first().unwrap().tool_call_id != "a"
    ): panic(
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

    if (
        not agent
        .context
        .messages
        .filter(
            fn(message: Message) -> Bool: (message.role == Role.ToolResult)
        )
        .first()
        .unwrap()
        .is_error
    ): panic(
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

# Pi core parity cases: compare scheduling and state, not only successful runs.

test "assistant continuation consumes exactly one steering batch":
    let agent = create_agent(
        Config(
            stream: complete,
            emit: ignore,
            finish_turn: some(
                fn(turn: Turn) -> Decision: Decision.End
            )
        )
    )

    if prompt(agent, [user("first")]).is_error(): panic("initial prompt failed")

    steer(
        agent,
        user("one")
    )
    steer(
        agent,
        user("two")
    )
    let resumed = continue_agent(agent)

    if resumed.is_error() or resumed.unwrap().length() != 2: panic(
        "queued continuation failed or drained twice"
    )

    if peek_queued_messages(agent).length() != 1: panic(
        "one-at-a-time steering drained twice"
    )

    clear_steering_queue(agent)
    follow_up(
        agent,
        user("follow")
    )

    if continue_agent(agent).is_error(): panic("follow-up continuation failed")

    if has_queued_messages(agent): panic("follow-up was not consumed")

test "queue inspection copies selected batch and clear methods are independent":
    let agent = create_agent(
        Config(stream: complete, emit: ignore, steering_mode: QueueMode.All)
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
        user("later")
    )
    let preview = peek_queued_messages(agent)
    preview.pop()

    if peek_queued_messages(agent).length() != 2: panic(
        "peek returned live queue storage"
    )

    clear_follow_up_queue(agent)

    if not has_queued_messages(agent): panic("clearing follow ups erased steering")

    clear_all_queues(agent)

    if has_queued_messages(agent): panic("queue clearing failed")

test "failed and aborted responses call finish but cannot continue":
    for reason in [StopReason.Failed, StopReason.Aborted]:
        let finished: List[StopReason] = []
        let model = fn(
            request: Request,
            control: Synchronized[Control],
            update: fn(message: Message) -> Unit
        ) -> Result[Message, Error]:
            return ok(
                Message(
                    Role.Assistant,
                    stop_reason: reason,
                    error_message: "stopped"
                )
            )
        let finish = fn(turn: Turn) -> Decision:
            finished.append(turn.message.stop_reason)
            return Decision.Continue
        let agent = create_agent(
            Config(
                stream: model,
                emit: ignore,
                finish_turn: some(finish)
            )
        )

        if prompt(agent, [user("go")]).is_ok(): panic("failure ignored")

        if finished != [reason]: panic("finish hook skipped or failure continued")

test "terminated tool batches still process follow ups":
    let requests: List[Int] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        requests.append(request.context.messages.length())
        if requests.length() == 1:
            return ok(
                Message(
                    Role.Assistant,
                    [Content.ToolCall("a", "echo", JsonValue.Null)],
                    StopReason.ToolUse
                )
            )

        return ok(Message(Role.Assistant))
    let before = fn(call: ToolCall, context: Context) -> Result[Preflight, Error]: ok(
        Preflight(blocked: true, terminate: true)
    )
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            before_tool_call: some(before)
        ),
        Context(tools: [tool()])
    )
    follow_up(
        agent,
        user("follow")
    )

    if prompt(agent, [user("go")]).is_error(): panic("terminated run failed")

    if requests.length() != 2 or has_queued_messages(agent): panic(
        "termination discarded queued input"
    )

test "finish continuation uses follow up without an extra empty request":
    let requests: List[Int] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        requests.append(request.context.messages.length())
        return ok(Message(Role.Assistant))
    let finish = fn(turn: Turn) -> Decision:
        if turn.new_messages.length() == 2: return Decision.Continue

        return Decision.End
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            finish_turn: some(finish)
        )
    )
    follow_up(
        agent,
        user("follow")
    )

    if prompt(agent, [user("go")]).is_error(): panic("explicit continuation failed")

    if requests != [1, 3]: panic("continuation did not coalesce with follow-up request")

test "next turn preparation appends messages with normal lifecycle events":
    let ended: List[Role] = []
    let sink = fn(event: Event) -> Unit:
        match event:
            MessageEnd(message): ended.append(message.role)
            _: return
    let finish = fn(turn: Turn) -> Decision:
        if turn.new_messages.length() == 2: return Decision.Continue

        return Decision.End
    let next = fn(turn: Turn) -> Request:
        return Request(turn.context, "changed", messages: [user("prepared")])
    let agent = create_agent(
        Config(
            stream: complete,
            emit: sink,
            finish_turn: some(finish),
            prepare_next_turn: some(next)
        )
    )
    let result = prompt(agent, [user("start")])

    if result.is_error() or result.unwrap().length() != 4: panic(
        "prepared message not returned"
    )

    if ended != [Role.User, Role.Assistant, Role.User, Role.Assistant]: panic(
        "prepared message lifecycle missing"
    )

test "tool declarations replay additions removals and changed schemas":
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(tools: [tool()])
    )

    if current_tools(agent.context.messages).length() != 1: panic(
        "initial tools not declared"
    )

    if prompt(agent, [user("one")]).is_error(): panic("initial declaration failed")

    let changed = tool()
    changed.description = "changed"
    set_tools(agent, [changed])
    let second = prompt(agent, [user("two")])

    if second.is_error(): panic("changed declaration failed")

    let delta = second.unwrap().first().unwrap()

    if (
        delta.role != Role.System
        or delta.tools_removed != ["echo"]
        or delta.tools_added.length() != 1
    ): panic("redefinition did not remove and add")

    set_tools(agent, [])

    if prompt(agent, [user("three")]).is_error(): panic("removal failed")

    if not current_tools(agent.context.messages).is_empty(): panic(
        "tool removal did not replay"
    )

    if reset(agent).is_error(): panic("reset failed")

    if (
        agent.context.messages.length() != 1
        or not current_tools(agent.context.messages).is_empty()
    ): panic("reset lost baseline or restored removed tool")

    if continue_agent(agent).is_ok(): panic("system-only continuation accepted")

test "pending system tool intent is replaced by executable loadout":
    let requested = Message(
        Role.System,
        [Content.Text("base")],
        tools_added: [ToolDeclaration("unavailable", "", JsonValue.Null)]
    )
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(tools: [tool()])
    )
    let result = prompt(agent, [requested, user("go")])

    if result.is_error(): panic("system prompt failed")

    let tools = current_tools(agent.context.messages)

    if tools.length() != 1 or tools.first().unwrap().name != "echo": panic(
        "pending intent overrode runtime tools"
    )

    if requested.tools_added.first().unwrap().name != "unavailable": panic(
        "caller system message was mutated"
    )

test "reset retains replayed prompt sections and clears conversation":
    let baseline = Message(
        Role.System,
        [Content.Text("base")],
        sections: {"a": some("old"), "b": some("remove")}
    )
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(messages: [baseline])
    )
    let update = Message(
        Role.System,
        [Content.Text("later")],
        sections: {"a": some("new"), "b": none}
    )

    if prompt(agent, [update, user("go")]).is_error(): panic("system update failed")

    if get_system_prompt(agent) != "base\n\nlater\n\nnew": panic("system replay failed")

    if reset(agent).is_error(): panic("reset failed")

    if (
        agent.context.messages.length() != 1
        or get_system_prompt(agent) != "base\n\nlater\n\nnew"
    ): panic("reset discarded system baseline")

    if collapse_system_messages([baseline, user("go"), update]).length() != 2: panic(
        "system collapse failed"
    )

test "text image prompts and setters retain independent outer lists":
    let agent = create_agent(Config(stream: complete, emit: ignore))
    let images = [Content.Image("data", "image/png")]
    let result = prompt_text(agent, "hello", images)

    if result.is_error() or result.unwrap().first().unwrap().content.length() != 2: panic(
        "text image prompt failed"
    )

    images.pop()

    if agent.context.messages.first().unwrap().content.length() != 2: panic(
        "prompt retained caller image list"
    )

    let messages = [user("replacement")]

    if replace_messages(agent, messages).is_error(): panic("replace failed")

    messages.pop()

    if agent.context.messages.length() != 1: panic("replace retained caller outer list")

    if append_message(
        agent,
        user("append")
    ).is_error(): panic("append failed")

    if prompt_message(
        agent,
        user("single")
    ).is_error(): panic("single prompt failed")

test "explicit host runtime supplies default stream and can be cleared":
    let runtime = StreamRuntime()
    set_default_stream_fn(
        runtime,
        some(complete)
    )
    let agent = create_agent(Config(emit: ignore, runtime: runtime))

    if prompt(agent, [user("go")]).is_error(): panic("default stream was not used")

    set_default_stream_fn(runtime, none)

    if prompt(agent, [user("again")]).is_ok(): panic("missing default stream accepted")

    if agent.is_streaming: panic("missing stream did not settle")

test "partial tool patches preserve omitted fields and drop stale structure":
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        return ok(
            ToolResult(
                [Content.Text("old")],
                details: JsonValue.StringValue("details"),
                structured_content: some(JsonValue.StringValue("old")),
                usage: some(Usage(input: 1))
            )
        )
    let patch = fn(
        call: ToolCall,
        result: ToolResult,
        context: Context
    ) -> Result[ToolResultPatch, Error]:
        return ok(
            ToolResultPatch(
                content: some([Content.Text("new")]),
                is_error: some(false)
            )
        )
    let agent = create_agent(
        Config(
            stream: complete,
            emit: ignore,
            after_tool_patch: some(patch)
        ),
        Context(
            tools: [
                Tool(
                    "echo",
                    "",
                    JsonValue.Null,
                    execute: execute
                )
            ]
        )
    )
    let outcome = run_tool_call_outcome(
        agent,
        ToolCall("a", "echo", JsonValue.Null),
        fn(result: ToolResult) -> Unit: unit
    )

    if (
        outcome.result.structured_content.is_some()
        or outcome.result.details != JsonValue.StringValue("details")
        or outcome.result.usage.is_none()
    ): panic("partial patch merge failed")

    if outcome.result.duration_ms.is_none(): panic("execution timing missing")

test "dynamic API keys resolve for every request and metadata is preserved":
    let keys: List[String] = []
    let resolve = fn(provider: String) -> Result[String, Error]:
        keys.append(provider)
        return ok("dynamic")
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        if field(request.options, "apiKey") != some(JsonValue.StringValue("dynamic")): panic(
            "dynamic key missing"
        )

        if (
            field(request.options, "sessionId") != some(
                JsonValue.StringValue("session")
            )
        ): panic("stream options missing")

        return ok(
            Message(
                Role.Assistant,
                usage: some(Usage(total_tokens: 5)),
                provider_thinking_level: "provider-level"
            )
        )
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            provider: "test",
            model: "model",
            thinking_level: "high",
            get_api_key: some(resolve),
            options: JsonValue.ObjectValue(
                {"sessionId": JsonValue.StringValue("session")}
            )
        )
    )

    if (
        prompt(agent, [user("one")]).is_error()
        or prompt(agent, [user("two")]).is_error()
    ): panic("key run failed")

    let message = agent.context.messages.last().unwrap()

    if (
        keys != ["test", "test"]
        or message.usage.unwrap().total_tokens != 5
        or message.thinking_level != "high"
        or message.timestamp_ms <= 0
    ): panic("metadata or key lifecycle lost")

test "automatic schema validation coerces arguments and removes optional nulls":
    let schema = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("object"),
            "properties": JsonValue.ObjectValue(
                {
                    "count": JsonValue.ObjectValue(
                        {
                            "type": JsonValue.StringValue(
                                "integer"
                            ),
                            "minimum": JsonValue.NumberValue(
                                "1"
                            )
                        }
                    ),
                    "optional": JsonValue.ObjectValue(
                        {
                            "type": JsonValue.StringValue(
                                "string"
                            )
                        }
                    )
                }
            ),
            "required": JsonValue.ArrayValue(
                [JsonValue.StringValue("count")]
            ),
            "additionalProperties": JsonValue.BoolValue(false)
        }
    )
    let seen: List[JsonValue] = []
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        seen.append(call.arguments)
        return ok(ToolResult())
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(
            tools: [
                Tool(
                    "echo",
                    "",
                    schema,
                    execute: execute
                )
            ]
        )
    )
    let raw = JsonValue.ObjectValue(
        {"count": JsonValue.StringValue("2"), "optional": JsonValue.Null}
    )
    let result = run_tool_call(
        agent,
        ToolCall("a", "echo", raw),
        fn(result: ToolResult) -> Unit: unit
    )

    if (
        result.is_error
        or field(
            seen.first().unwrap(),
            "count"
        ) != some(JsonValue.NumberValue("2"))
        or field(
            (seen.first().unwrap()),
            "optional"
        ).is_some()
    ): panic("schema normalization failed")

    if field(raw, "optional").is_none(): panic(
        "schema normalization mutated raw arguments"
    )

    let invalid = run_tool_call(
        agent,
        ToolCall(
            "b",
            "echo",
            JsonValue.ObjectValue({"extra": JsonValue.BoolValue(true)})
        ),
        fn(result: ToolResult) -> Unit: unit
    )

    if not invalid.is_error or seen.length() != 1: panic(
        "invalid schema arguments executed"
    )

test "schema unions local references array and pattern constraints":
    let definition = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("string"),
            "pattern": JsonValue.StringValue("^a"),
            "minLength": JsonValue.NumberValue("2")
        }
    )
    let schema = JsonValue.ObjectValue(
        {
            "$defs": JsonValue.ObjectValue({"word": definition}),
            "type": JsonValue.StringValue("array"),
            "items": JsonValue.ObjectValue(
                {"$ref": JsonValue.StringValue("#/$defs/word")}
            ),
            "minItems": JsonValue.NumberValue("1"),
            "uniqueItems": JsonValue.BoolValue(true)
        }
    )

    if validate_arguments(
        schema,
        JsonValue.ArrayValue([JsonValue.StringValue("ab")])
    ).is_error(): panic("valid referenced array rejected")

    if validate_arguments(
        schema,
        JsonValue.ArrayValue([JsonValue.StringValue("bb")])
    ).is_ok(): panic("pattern ignored")

    if validate_arguments(
        schema,
        JsonValue.ArrayValue(
            [JsonValue.StringValue("ab"), JsonValue.StringValue("ab")]
        )
    ).is_ok(): panic("uniqueness ignored")

    let union = JsonValue.ObjectValue(
        {
            "anyOf": JsonValue.ArrayValue(
                [
                    JsonValue.ObjectValue(
                        {
                            "type": JsonValue.StringValue(
                                "integer"
                            )
                        }
                    ),
                    JsonValue.ObjectValue(
                        {
                            "type": JsonValue.StringValue(
                                "boolean"
                            )
                        }
                    )
                ]
            )
        }
    )

    if (
        validate_arguments(
            union,
            JsonValue.StringValue("true")
        ).unwrap() != JsonValue.BoolValue(true)
    ): panic("union coercion failed")

    if validate_arguments(
        JsonValue.ObjectValue({"unknownAssertion": JsonValue.BoolValue(true)}),
        JsonValue.Null
    ).is_ok(): panic("unsupported schema silently accepted")

test "output schema checks are available explicitly without changing Pi dispatch":
    let schema = JsonValue.ObjectValue({"type": JsonValue.StringValue("integer")})

    if validate_output(
        schema,
        JsonValue.StringValue("2")
    ).is_ok(): panic("output checker coerced invalid structure")

    if validate_output(
        schema,
        JsonValue.NumberValue("2")
    ).is_error(): panic("output checker rejected valid structure")

test "idle waiting includes end listener settlement":
    let reached = Synchronized(false)
    let release = Synchronized(false)
    let config = Config(stream: complete, emit: ignore)
    let agent = create_agent(config)
    let listener = fn(event: Event) -> Unit:
        match event:
            AgentEnd(_):
                with guard = reached.lock(): guard.set(true)

                while true:
                    var ready = false

                    with guard = release.lock(): ready = guard.get()

                    if ready: return

                    yield_now()
            _: return
    let _unsubscribe = subscribe(agent, listener)

    with tasks = TaskGroup():
        let run = tasks.start(
            fn() -> Result[List[Message], Error]: prompt(
                agent,
                [user("go")]
            )
        )

        while true:
            var ready = false

            with guard = reached.lock(): ready = guard.get()

            if ready: break

            yield_now()

        if active_signal(agent).is_none(): panic(
            "signal disappeared before listener settled"
        )

        let waiter = tasks.start(
            fn() -> Unit: wait_for_idle(agent)
        )

        with guard = release.lock(): guard.set(true)

        if run.join().unwrap().is_error(): panic("run failed")

        let _waited = waiter.join().unwrap()

        if active_signal(agent).is_some(): panic("idle wait ended before settlement")

test "programming faults release run state through scoped cleanup":
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]: panic("provider programming fault")
    let agent = create_agent(Config(stream: model, emit: ignore))

    with tasks = TaskGroup():
        let run = tasks.start(
            fn() -> Result[List[Message], Error]: prompt(
                agent,
                [user("go")]
            )
        )

        if run.join().is_ok(): panic("programming fault was swallowed")

    if agent.is_streaming or active_signal(agent).is_some(): panic(
        "fault left agent busy"
    )

fn proxy_event(kind: String, position: Int = 0, delta: String = "") -> JsonValue:
    return JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue(kind),
            "contentIndex": JsonValue.NumberValue(position.toString()),
            "delta": JsonValue.StringValue(delta)
        }
    )

test "proxy reconstructs thinking text tools signatures and terminal usage":
    let state = ProxyState()

    if process_proxy_event(
        state,
        proxy_event("thinking_start")
    ).is_error(): panic("thinking start failed")

    if process_proxy_event(
        state,
        proxy_event("thinking_delta", delta: "reason")
    ).is_error(): panic("thinking delta failed")

    let thinking_end = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("thinking_end"),
            "contentIndex": JsonValue.NumberValue("0"),
            "contentSignature": JsonValue.StringValue("signature")
        }
    )

    if process_proxy_event(state, thinking_end).is_error(): panic("thinking end failed")

    let start = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("toolcall_start"),
            "contentIndex": JsonValue.NumberValue("1"),
            "id": JsonValue.StringValue("tool-1"),
            "toolName": JsonValue.StringValue("echo")
        }
    )

    if process_proxy_event(state, start).is_error(): panic("tool start failed")

    if process_proxy_event(
        state,
        proxy_event("toolcall_delta", 1, "\{\"count\":1")
    ).is_error(): panic("partial JSON failed")

    let partial = state.message.content[1].unwrap()

    match partial:
        ToolCall(_, _, arguments):
            if field(arguments, "count") != some(JsonValue.NumberValue("1")): panic(
                "streaming JSON salvage failed"
            )
        _: panic("wrong tool content")

    let final = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("toolcall_end"),
            "contentIndex": JsonValue.NumberValue("1"),
            "toolCall": JsonValue.ObjectValue(
                {
                    "id": JsonValue.StringValue("tool-1"),
                    "name": JsonValue.StringValue("echo"),
                    "arguments": JsonValue.ObjectValue(
                        {"count": JsonValue.NumberValue("1")}
                    )
                }
            )
        }
    )

    if process_proxy_event(state, final).is_error(): panic("tool end failed")

    let done = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("done"),
            "reason": JsonValue.StringValue("toolUse"),
            "usage": JsonValue.ObjectValue(
                {"totalTokens": JsonValue.NumberValue("7")}
            )
        }
    )

    if process_proxy_event(state, done).is_error(): panic("terminal event failed")

    if (
        not state.terminal
        or state.message.stop_reason != StopReason.ToolUse
        or state.message.usage.unwrap().total_tokens != 7
    ): panic("terminal state missing")

    if (
        state.message.content_signatures.get(0) != some("signature")
        or not state.fragments.is_empty()
    ): panic("content metadata not finalized")

test "proxy rejects invalid ordering mismatched deltas and unknown reasons":
    let state = ProxyState()

    if process_proxy_event(
        state,
        proxy_event("text_delta", delta: "bad")
    ).is_ok(): panic("delta before start accepted")

    if process_proxy_event(
        state,
        proxy_event("text_start", 2)
    ).is_ok(): panic("skipped index accepted")

    if process_proxy_event(
        state,
        proxy_event("text_start")
    ).is_error(): panic("valid start rejected")

    if process_proxy_event(
        state,
        proxy_event("thinking_delta", delta: "bad")
    ).is_ok(): panic("mismatched delta accepted")

    let error_event = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("error"),
            "reason": JsonValue.StringValue("aborted"),
            "errorMessage": JsonValue.StringValue("cancelled")
        }
    )

    if (
        process_proxy_event(state, error_event).is_error()
        or state.message.stop_reason != StopReason.Aborted
    ): panic("abort event failed")

    if process_proxy_event(
        state,
        proxy_event("start")
    ).is_ok(): panic("event after termination accepted")

test "proxy payload contains transcript declarations and whitelisted options":
    let declared = ToolDeclaration(
        "echo",
        "echo",
        JsonValue.ObjectValue({"type": JsonValue.StringValue("object")})
    )
    let message = Message(
        Role.System,
        [Content.Text("base")],
        tools_added: [declared],
        tools_removed: ["old"]
    )
    let request = Request(
        Context(messages: [message]),
        "model",
        "high",
        options: JsonValue.ObjectValue(
            {
                "apiKey": JsonValue.StringValue("secret"),
                "sessionId": JsonValue.StringValue("session"),
                "onPayload": JsonValue.StringValue("invalid")
            }
        ),
        model_descriptor: JsonValue.ObjectValue(
            {"id": JsonValue.StringValue("model")}
        )
    )
    let payload = proxy_payload(request)
    let options = field(payload, "options").unwrap()

    if field(options, "apiKey").is_some() or field(options, "onPayload").is_some(): panic(
        "proxy serialized local-only options"
    )

    if field(options, "reasoning") != some(JsonValue.StringValue("high")): panic(
        "proxy reasoning missing"
    )

    let wire = message_json(message)

    if (
        field(wire, "toolsAdded").is_none()
        or field(wire, "toolsRemoved").is_none()
        or field(wire, "content") != some(JsonValue.StringValue("base"))
    ): panic("proxy transcript protocol missing")

test "schema conjunction negation numeric enums and tuple tails":
    let integer = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("integer"),
            "minimum": JsonValue.NumberValue("1"),
            "exclusiveMaximum": JsonValue.NumberValue("4"),
            "multipleOf": JsonValue.NumberValue("1")
        }
    )
    let schema = JsonValue.ObjectValue(
        {
            "allOf": JsonValue.ArrayValue([integer]),
            "not": JsonValue.ObjectValue(
                {"const": JsonValue.NumberValue("3")}
            ),
            "enum": JsonValue.ArrayValue(
                [
                    JsonValue.NumberValue("1.0"),
                    JsonValue.NumberValue("2.0")
                ]
            )
        }
    )

    if validate_arguments(
        schema,
        JsonValue.NumberValue("1")
    ).is_error(): panic("numeric JSON identity or conjunction failed")

    if validate_arguments(
        schema,
        JsonValue.NumberValue("3")
    ).is_ok(): panic("negation ignored")

    let tuple = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("array"),
            "prefixItems": JsonValue.ArrayValue([integer]),
            "items": JsonValue.BoolValue(false)
        }
    )

    if validate_arguments(
        tuple,
        JsonValue.ArrayValue([JsonValue.NumberValue("1")])
    ).is_error(): panic("tuple first item failed")

    if validate_arguments(
        tuple,
        JsonValue.ArrayValue(
            [JsonValue.NumberValue("1"), JsonValue.NumberValue("2")]
        )
    ).is_ok(): panic("tuple tail schema ignored")

test "schema conditionals property patterns and dependencies":
    let schema = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("object"),
            "patternProperties": JsonValue.ObjectValue(
                {
                    "^x": JsonValue.ObjectValue(
                        {
                            "type": JsonValue.StringValue(
                                "integer"
                            )
                        }
                    )
                }
            ),
            "additionalProperties": JsonValue.BoolValue(false),
            "dependentRequired": JsonValue.ObjectValue(
                {
                    "x": JsonValue.ArrayValue(
                        [JsonValue.StringValue("xy")]
                    )
                }
            )
        }
    )

    if validate_arguments(
        schema,
        JsonValue.ObjectValue({"x": JsonValue.NumberValue("1")})
    ).is_ok(): panic("dependency ignored")

    if validate_arguments(
        schema,
        JsonValue.ObjectValue(
            {
                "x": JsonValue.StringValue("1"),
                "xy": JsonValue.NumberValue("2")
            }
        )
    ).is_error(): panic("pattern property coercion failed")

    let conditional = JsonValue.ObjectValue(
        {
            "if": JsonValue.ObjectValue(
                {"type": JsonValue.StringValue("integer")}
            ),
            "then": JsonValue.ObjectValue(
                {"minimum": JsonValue.NumberValue("2")}
            ),
            "else": JsonValue.ObjectValue(
                {"const": JsonValue.StringValue("other")}
            )
        }
    )

    if validate_arguments(
        conditional,
        JsonValue.NumberValue("1")
    ).is_ok(): panic("conditional numeric branch ignored")

    if validate_arguments(
        conditional,
        JsonValue.StringValue("other")
    ).is_error(): panic("conditional else failed")

test "sequential abort stops admission of remaining calls":
    let executed: List[String] = []
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        executed.append(call.id)

        with guard = control.lock(): guard.get().aborted = true

        return ok(ToolResult())
    let agent = create_agent(
        Config(
            stream: two_calls,
            emit: ignore,
            tool_execution: ExecutionMode.Sequential
        ),
        Context(
            tools: [
                Tool(
                    "echo",
                    "",
                    JsonValue.Null,
                    execute: execute
                )
            ]
        )
    )

    if prompt(agent, [user("go")]).is_ok(): panic("abort did not fail run")

    if (
        executed != ["a"]
        or agent.context.messages.filter(
            fn(message: Message) -> Bool: (message.role == Role.ToolResult)
        ).length() != 1
    ): panic("sequential abort admitted remaining calls")

test "provider raw events arrive before message updates and stop after settlement":
    let events: List[Event] = []
    let callbacks: List[fn(event: JsonValue) -> Unit] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        callbacks.append(request.provider_event.unwrap())
        request.provider_event.unwrap()(proxy_event("start"))
        update(Message(Role.Assistant, [Content.Text("partial")]))
        return ok(Message(Role.Assistant))
    let sink = fn(event: Event) -> Unit:
        match event:
            ProviderUpdate(_): events.append(event)
            MessageUpdate(_): events.append(event)
            _: return
    let agent = create_agent(Config(stream: model, emit: sink))

    if prompt(agent, [user("go")]).is_error(): panic("provider event run failed")

    callbacks.first().unwrap()(proxy_event("start"))

    if events.length() != 2: panic("late provider event accepted")

    match events.first().unwrap():
        ProviderUpdate(_): return
        _: panic("provider event was reordered")

test "steering queued by initial turn listeners reaches the first request":
    let seen: List[Int] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        seen.append(request.context.messages.length())
        return ok(Message(Role.Assistant))
    let agent = create_agent(
        Config(
            stream: model,
            emit: ignore,
            finish_turn: some(
                fn(turn: Turn) -> Decision: Decision.End
            )
        )
    )
    let _unsubscribe = subscribe(
        agent,
        fn(event: Event) -> Unit:
            match event:
                TurnStart: steer(
                    agent,
                    user("from listener")
                )
                _: return
    )

    if prompt(agent, [user("go")]).is_error(): panic("initial steering run failed")

    if seen != [2] or has_queued_messages(agent): panic(
        "initial listener steering was delayed"
    )

test "all hooks in a sequential batch see the same assistant context":
    let contexts: List[Int] = []
    let before = fn(call: ToolCall, context: Context) -> Result[Preflight, Error]:
        contexts.append(context.messages.length())

        if (
            call.assistant_message.is_none()
            or call.original_arguments != some(JsonValue.Null)
            or call.control.is_none()
        ): panic("hook call context is incomplete")

        return ok(Preflight())
    let agent = create_agent(
        Config(
            stream: two_calls,
            emit: ignore,
            tool_execution: ExecutionMode.Sequential,
            before_tool_call: some(before)
        ),
        Context(tools: [tool()])
    )

    if prompt(agent, [user("go")]).is_error(): panic("sequential context run failed")

    if contexts.length() != 2 or contexts[0].unwrap() != contexts[1].unwrap(): panic(
        "hook context included partial tool batch"
    )

test "schema format validation composes builtins with native predicates":
    let date = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("string"),
            "format": JsonValue.StringValue("date")
        }
    )

    if validate_arguments(
        date,
        JsonValue.StringValue("2026-02-30")
    ).is_ok(): panic("invalid calendar date accepted")

    if validate_arguments(
        date,
        JsonValue.StringValue("2026-10-14")
    ).is_error(): panic("valid date rejected")

    let uuid = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("string"),
            "format": JsonValue.StringValue("uuid")
        }
    )

    if validate_arguments(
        uuid,
        JsonValue.StringValue("123e4567-e89b-12d3-a456-426614174000")
    ).is_error(): panic("valid UUID rejected")

    let custom = JsonValue.ObjectValue(
        {
            "type": JsonValue.StringValue("string"),
            "format": JsonValue.StringValue("agent-id")
        }
    )
    let formats: Map[String, fn(value: String) -> Bool] = {
        "agent-id": fn(value: String) -> Bool: value.starts_with("agent-")
    }

    if validate_arguments(
        custom,
        JsonValue.StringValue("agent-1"),
        formats: formats
    ).is_error(): panic("custom format predicate ignored")

    if validate_arguments(
        custom,
        JsonValue.StringValue("other"),
        formats: formats
    ).is_ok(): panic("custom format failure ignored")

test "programming faults revoke saved provider and tool update callbacks":
    let provider_callbacks: List[fn(message: Message) -> Unit] = []
    let tool_callbacks: List[fn(result: ToolResult) -> Unit] = []
    let updates: List[Event] = []
    let provider = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        provider_callbacks.append(update)
        panic("provider fault")
    let execute = fn(
        call: ToolCall,
        control: Synchronized[Control],
        update: fn(result: ToolResult) -> Unit
    ) -> Result[ToolResult, Error]:
        tool_callbacks.append(update)
        panic("tool fault")
    let sink = fn(event: Event) -> Unit:
        match event:
            MessageUpdate(_): updates.append(event)
            ToolUpdate(_, _): updates.append(event)
            _: return
    let agent = create_agent(
        Config(stream: provider, emit: sink),
        Context(
            tools: [
                Tool(
                    "echo",
                    "",
                    JsonValue.Null,
                    execute: execute
                )
            ]
        )
    )

    with tasks = TaskGroup():
        let run = tasks.start(
            fn() -> Result[List[Message], Error]: prompt(
                agent,
                [user("go")]
            )
        )

        if run.join().is_ok(): panic("provider fault swallowed")

    provider_callbacks.first().unwrap()(Message(Role.Assistant))

    with tasks = TaskGroup():
        let call = tasks.start(
            fn() -> ToolResult: run_tool_call(
                agent,
                ToolCall("a", "echo", JsonValue.Null),
                fn(result: ToolResult) -> Unit: sink(
                    Event.ToolUpdate(
                        ToolCall("a", "echo", JsonValue.Null),
                        result
                    )
                )
            )
        )

        if call.join().is_ok(): panic("tool fault swallowed")

    tool_callbacks.first().unwrap()(ToolResult())

    if not updates.is_empty() or agent.streaming_message.is_some(): panic(
        "fault left a live update callback"
    )

test "low level loops accept empty prompts and system-only continuation":
    let config = Config(stream: complete, emit: ignore)
    let empty = run_agent_loop(
        [],
        Context(),
        config
    )

    if empty.is_error() or empty.unwrap().length() != 1: panic(
        "empty low-level prompt rejected"
    )

    let system = run_agent_loop_continue(
        Context(messages: [Message(Role.System, [Content.Text("base")])]),
        config
    )

    if system.is_error() or system.unwrap().length() != 1: panic(
        "low-level system continuation rejected"
    )

    let agent = create_agent(
        config,
        Context(messages: [Message(Role.System)])
    )

    if continue_agent(agent).is_ok(): panic(
        "high-level system-only continuation accepted"
    )

test "additional native validation cannot bypass the declared schema":
    let schema = JsonValue.ObjectValue({"type": JsonValue.StringValue("integer")})
    let rewrite = fn(arguments: JsonValue) -> Result[JsonValue, Error]: ok(
        JsonValue.StringValue("invalid")
    )
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        Context(
            tools: [
                Tool(
                    "echo",
                    "",
                    schema,
                    validate: some(rewrite),
                    execute: echo
                )
            ]
        )
    )
    let result = run_tool_call(
        agent,
        ToolCall(
            "a",
            "echo",
            JsonValue.NumberValue("2")
        ),
        fn(result: ToolResult) -> Unit: unit
    )

    if not result.is_error: panic("native validator bypassed schema enforcement")

test "high level baseline seeding and low level tool deltas remain distinct":
    let context = Context(messages: [user("history")], tools: [tool()])
    let agent = create_agent(
        Config(stream: complete, emit: ignore),
        context
    )

    if agent.context.messages.first().unwrap().role != Role.System: panic(
        "high-level tool baseline was not prepended"
    )

    if context.messages.length() != 1: panic("baseline seeding mutated caller history")

    let result = run_agent_loop(
        [user("new")],
        context,
        Config(stream: complete, emit: ignore)
    )

    if result.is_error(): panic("low-level loop failed")

    if result.unwrap().first().unwrap().role != Role.System: panic(
        "low-level loop omitted tool delta from new messages"
    )

    let system = Message(Role.System, [Content.Text("first"), Content.Text("second")])

    if (
        get_system_prompt(
            create_agent(
                Config(stream: complete, emit: ignore),
                Context(messages: [system])
            )
        ) != "first\nsecond"
    ): panic("system text block separator differs from Pi")

test "cancellation tokens retain their run identity across later runs":
    let tokens: List[Synchronized[Control]] = []
    let model = fn(
        request: Request,
        control: Synchronized[Control],
        update: fn(message: Message) -> Unit
    ) -> Result[Message, Error]:
        tokens.append(control)

        if tokens.length() == 1:
            with guard = control.lock(): guard.get().aborted = true

        return ok(Message(Role.Assistant))
    let agent = create_agent(Config(stream: model, emit: ignore))

    if prompt(agent, [user("first")]).is_ok(): panic("first token did not abort")

    let old = tokens.first().unwrap()

    if prompt(agent, [user("second")]).is_error(): panic(
        "old cancellation affected new run"
    )

    if not is_aborted(old) or is_aborted(tokens.last().unwrap()): panic(
        "run token identity was reset or shared"
    )

    if active_signal(agent).is_some(): panic(
        "completed run still exposes an active signal"
    )

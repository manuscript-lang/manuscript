import {
    Content,
    Role,
    StopReason,
    Message,
    ToolResult,
    ToolCall,
    ExecutionMode,
    QueueMode,
    Control,
    Tool,
    Context,
    Request,
    Turn,
    Decision,
    Preflight,
    Event,
    Config,
    AgentError
} from "./types.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import Synchronized from "@std/sync.ms"

# State is confined to the caller task. Control alone may be shared across tasks.
export type Subscription:
    listener: fn(event: Event) -> Unit
    active: Bool = true

export type Agent:
    config: Config
    context: Context = Context()
    control: Synchronized[Control] = Synchronized(Control())
    is_streaming: Bool = false
    streaming_message: Optional[Message] = none
    pending_tool_calls: List[String] = []
    error_message: String = ""
    subscriptions: List[Subscription] = []

export fn create_agent(
    config: Config,
    context: Context = Context()
) -> Agent:
    return Agent(
        config,
        Context(
            context.messages.clone(),
            context.tools.clone()
        )
    )

# Subscriptions are changed by the owner task or a serialized event callback.
export fn subscribe(agent: Agent, listener: fn(event: Event) -> Unit) -> fn() -> Unit:
    let subscription = Subscription(listener)
    agent.subscriptions.append(subscription)
    return fn() -> Unit:
        subscription.active = false

fn dispatch(agent: Agent, event: Event) -> Unit:
    agent.config.emit(event)

    for subscription in agent.subscriptions.clone():
        if subscription.active:
            subscription.listener(event)

# Low-level entrypoints copy the outer transcript and return only new messages.
export fn run_agent_loop(
    prompts: List[Message],
    context: Context,
    config: Config
) -> Result[List[Message], Error]:
    return prompt(
        create_agent(config, context),
        prompts
    )

export fn run_agent_loop_continue(
    context: Context,
    config: Config
) -> Result[List[Message], Error]:
    return continue_agent(create_agent(config, context))

export fn abort(agent: Agent) -> Unit:
    with guard = agent.control.lock():
        guard.get().aborted = true

export fn steer(agent: Agent, message: Message) -> Unit:
    with guard = agent.control.lock():
        guard.get().steering.append(message)

export fn follow_up(agent: Agent, message: Message) -> Unit:
    with guard = agent.control.lock():
        guard.get().follow_up.append(message)

export fn is_aborted(control: Synchronized[Control]) -> Bool:
    with guard = control.lock():
        return guard.get().aborted

export fn reset(agent: Agent) -> Result[Unit, AgentError]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Cannot reset a running agent"))

    agent.context.messages = []
    agent.error_message = ""
    agent.streaming_message = none
    agent.pending_tool_calls = []

    with guard = agent.control.lock():
        guard.set(Control())

    return ok(unit)

export fn prompt(agent: Agent, messages: List[Message]) -> Result[List[Message], Error]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Agent is already running"))
    if messages.is_empty():
        return error(AgentError.InvalidState("Prompt must contain a message"))

    return run(agent, messages)

export fn continue_agent(agent: Agent) -> Result[List[Message], Error]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Agent is already running"))
    if agent.context.messages.is_empty():
        return error(AgentError.InvalidState("Cannot continue: no messages in context"))
    if agent.context.messages.last().unwrap().role == Role.Assistant:
        return error(
            AgentError.InvalidState(
                "Cannot continue from an assistant message"
            )
        )

    return run(agent, [])

fn drain(
    control: Synchronized[Control],
    steering: Bool,
    mode: QueueMode
) -> List[Message]:
    with guard = control.lock():
        let state = guard.get()
        var queue = state.follow_up

        if steering:
            queue = state.steering

        if queue.is_empty():
            return []

        var count = queue.length()

        if mode == QueueMode.OneAtATime:
            count = 1

        let result = queue.take(count)
        queue.splice(0, count, [])
        return result

fn emit_message(agent: Agent, message: Message, fresh: List[Message]) -> Unit:
    agent.context.messages.append(message)
    fresh.append(message)
    dispatch(
        agent,
        Event.MessageStart(message)
    )
    dispatch(
        agent,
        Event.MessageEnd(message)
    )

fn fail_result(message: String) -> ToolResult:
    return ToolResult(content: [Content.Text(message)], is_error: true)

type PreparedCall:
    tool: Tool
    call: ToolCall

fn prepare_tool(agent: Agent, call: ToolCall) -> Result[PreparedCall, Error]:
    let selected = (
        agent
        .context
        .tools
        .find(
            fn(tool: Tool) -> Bool: (tool.name == call.name)
        )
    )
    if selected.is_none():
        return error(AgentError.InvalidState("Tool {call.name} not found"))

    let tool = selected.unwrap()
    let arguments = try tool.validate(call.arguments)
    return ok(
        PreparedCall(
            tool,
            ToolCall(call.id, call.name, arguments)
        )
    )

# No events or transcript writes: usable by tools that invoke other tools.
export fn run_tool_call(
    agent: Agent,
    call: ToolCall,
    update: fn(result: ToolResult) -> Unit
) -> ToolResult:
    let prepared = prepare_tool(agent, call)

    let tool = match prepared:
        ok(value): value
        error(cause): return fail_result(cause.message())

    let permission = match preflight(agent, tool.call):
        ok(value): value
        error(cause): return fail_result(cause.message())

    if is_aborted(agent.control):
        return fail_result("Operation aborted")

    if permission.blocked:
        let blocked = fail_result(permission.reason)
        blocked.terminate = permission.terminate
        return blocked

    return finalize(
        agent,
        tool.call,
        execute_tool(
            agent,
            tool.tool,
            tool.call,
            update
        )
    )

fn preflight(agent: Agent, call: ToolCall) -> Result[Preflight, Error]:
    match agent.config.before_tool_call:
        some(hook): return hook(call, agent.context)
        none: return ok(Preflight())

fn finalize(agent: Agent, call: ToolCall, result: ToolResult) -> ToolResult:
    if agent.config.after_tool_call.is_none():
        return result

    match agent.config.after_tool_call.unwrap()(call, result, agent.context):
        ok(value): return value
        error(cause): return fail_result(cause.message())

fn execute_tool(
    agent: Agent,
    tool: Tool,
    call: ToolCall,
    update: fn(result: ToolResult) -> Unit
) -> ToolResult:
    if is_aborted(agent.control):
        return fail_result("Operation aborted")

    let accepting = Synchronized(true)
    let guarded_update = fn(result: ToolResult) -> Unit:
        with guard = accepting.lock():
            if guard.get():
                update(result)

    let result = match tool.execute(call, agent.control, guarded_update):
        ok(value): value
        error(cause): fail_result(cause.message())

    with guard = accepting.lock():
        guard.set(false)

    return result

fn calls_from(message: Message) -> List[ToolCall]:
    let calls: List[ToolCall] = []

    for block in message.content:
        match block:
            ToolCall(id, name, arguments): calls.append(ToolCall(id, name, arguments))
            _: continue

    return calls

fn tool_message(call: ToolCall, result: ToolResult) -> Message:
    return Message(
        Role.ToolResult,
        result.content,
        tool_call_id: call.id,
        tool_name: call.name,
        is_error: result.is_error,
        details: result.details
    )

# The event gate serializes sinks even when tool callbacks run concurrently.
fn execute_batch(
    agent: Agent,
    message: Message,
    fresh: List[Message]
) -> Result[List[ToolResult], Error]:
    let calls = calls_from(message)
    let results: List[ToolResult] = []
    var sequential = agent.config.tool_execution == ExecutionMode.Sequential

    for call in calls:
        let tool = (
            agent
            .context
            .tools
            .find(
                fn(tool: Tool) -> Bool: (tool.name == call.name)
            )
        )

        if (
            tool.is_some()
            and tool.unwrap().execution_mode == some(
                ExecutionMode.Sequential
            )
        ):
            sequential = true

    let gate = Synchronized(agent)

    if sequential or message.stop_reason == StopReason.Length:
        for call in calls:
            agent.pending_tool_calls.append(call.id)
            dispatch(
                agent,
                Event.ToolStart(call)
            )
            var result = fail_result(
                "Tool arguments may be truncated; re-issue the call"
            )

            if message.stop_reason != StopReason.Length:
                result = run_tool_call(
                    agent,
                    call,
                    fn(result: ToolResult) -> Unit: (
                        dispatch(
                            agent,
                            Event.ToolUpdate(call, result)
                        )
                    )
                )

            agent.pending_tool_calls = (
                agent
                .pending_tool_calls
                .filter(
                    fn(id: String) -> Bool: (id != call.id)
                )
            )
            dispatch(
                agent,
                Event.ToolEnd(call, result)
            )
            results.append(result)
            emit_message(
                agent,
                tool_message(call, result),
                fresh
            )

        agent.pending_tool_calls = []
        return ok(results)

    # Validation and admission run in source order before concurrent execution.
    let prepared: List[Optional[PreparedCall]] = []

    for call in calls:
        agent.pending_tool_calls.append(call.id)
        dispatch(
            agent,
            Event.ToolStart(call)
        )
        var tool: Optional[PreparedCall] = none
        var result = fail_result("Tool not found")

        match prepare_tool(agent, call):
            ok(value): tool = some(value)
            error(cause): result = fail_result(cause.message())

        if tool.is_some():
            var permission = Preflight()

            match preflight(agent, tool.unwrap().call):
                ok(value): permission = value
                error(cause):
                    result = fail_result(cause.message())
                    tool = none

            if is_aborted(agent.control):
                result = fail_result("Operation aborted")
                tool = none

            if permission.blocked:
                result = fail_result(permission.reason)
                result.terminate = permission.terminate
                tool = none

        prepared.append(tool)
        results.append(result)

    with tasks = TaskGroup():
        let handles: List[Task[ToolResult]] = []

        for entry in calls.entries():
            let call = entry.value
            let tool = prepared[entry.index].unwrap()
            let initial = results[entry.index].unwrap()
            handles.append(
                tasks.start(
                    fn() -> ToolResult:
                        var result = initial

                        if tool.is_some():
                            result = execute_tool(
                                agent,
                                tool.unwrap().tool,
                                tool.unwrap().call,
                                fn(
                                    result: ToolResult
                                ) -> Unit:
                                    with guard = gate.lock():
                                        dispatch(
                                            guard.get(),
                                            Event.ToolUpdate(
                                                call,
                                                result
                                            )
                                        )
                            )

                        with guard = gate.lock():
                            if tool.is_some():
                                result = finalize(
                                    guard.get(),
                                    tool.unwrap().call,
                                    result
                                )

                            guard.get().pending_tool_calls = (
                                guard
                                .get()
                                .pending_tool_calls
                                .filter(
                                    fn(
                                        id: String
                                    ) -> Bool: (id != call.id)
                                )
                            )
                            dispatch(
                                guard.get(),
                                Event.ToolEnd(
                                    call,
                                    result
                                )
                            )

                        return result
                )
            )

        let _joined = try tasks.join()

        for entry in handles.entries():
            results.set(
                entry.index,
                try entry.value.join()
            )

    agent.pending_tool_calls = []

    for entry in calls.entries():
        emit_message(
            agent,
            tool_message(
                entry.value,
                results[entry.index].unwrap()
            ),
            fresh
        )

    return ok(results)

fn transform(config: Config, messages: List[Message]) -> Result[List[Message], Error]:
    var result = messages.clone()

    if config.transform_context.is_some():
        result = try config.transform_context.unwrap()(result)

    if config.convert_to_llm.is_some():
        result = try config.convert_to_llm.unwrap()(result)

    return ok(result)

fn response(agent: Agent, request: Request) -> Message:
    let partial = Message(Role.Assistant)
    let index = agent.context.messages.length()
    agent.context.messages.append(partial)
    agent.streaming_message = some(partial)
    dispatch(
        agent,
        Event.MessageStart(partial)
    )
    let accepting = Synchronized(true)
    let update = fn(message: Message) -> Unit:
        with guard = accepting.lock():
            if guard.get():
                agent.streaming_message = some(message)
                agent.context.messages.set(index, message)
                dispatch(
                    agent,
                    Event.MessageUpdate(message)
                )

    var result = match agent.config.stream(request, agent.control, update):
        ok(value): value
        error(cause): Message(
            Role.Assistant,
            stop_reason: StopReason.Failed,
            error_message: cause.message()
        )

    with guard = accepting.lock():
        guard.set(false)

    if is_aborted(agent.control):
        result.stop_reason = StopReason.Aborted
        result.error_message = "Operation aborted"

    if result.role != Role.Assistant:
        result = Message(
            Role.Assistant,
            stop_reason: StopReason.Failed,
            error_message: "Provider returned a non-assistant message"
        )

    agent.context.messages.set(index, result)
    agent.streaming_message = none
    dispatch(
        agent,
        Event.MessageEnd(result)
    )
    return result

fn run(agent: Agent, prompts: List[Message]) -> Result[List[Message], Error]:
    agent.is_streaming = true
    agent.error_message = ""

    with guard = agent.control.lock():
        guard.get().aborted = false

    let fresh: List[Message] = []
    dispatch(agent, Event.AgentStart)
    let outcome = run_turns(agent, prompts, fresh)
    agent.streaming_message = none
    agent.pending_tool_calls = []

    match outcome:
        ok(_): agent.error_message = ""
        error(cause): agent.error_message = cause.message()

    # Listeners settle before the agent becomes idle.
    dispatch(
        agent,
        Event.AgentEnd(fresh.clone())
    )
    agent.is_streaming = false
    let _completed = try outcome
    return ok(fresh)

fn fail_turn(
    agent: Agent,
    message: String,
    reason: StopReason,
    fresh: List[Message]
) -> Result[Unit, Error]:
    let failed = Message(Role.Assistant, stop_reason: reason, error_message: message)
    emit_message(agent, failed, fresh)
    dispatch(
        agent,
        Event.TurnEnd(failed, [])
    )
    return error(AgentError.InvalidState(message))

fn run_turns(
    agent: Agent,
    prompts: List[Message],
    fresh: List[Message]
) -> Result[Unit, Error]:
    var pending = prompts.concat(drain(agent.control, true, agent.config.steering_mode))
    var request = Request(
        agent.context,
        agent.config.model,
        agent.config.thinking_level
    )
    var previous: Optional[Turn] = none

    while true:
        if previous.is_some() and agent.config.prepare_next_turn.is_some():
            request = agent.config.prepare_next_turn.unwrap()(previous.unwrap())
            agent.context = request.context
            agent.config.model = request.model
            agent.config.thinking_level = request.thinking_level

        dispatch(agent, Event.TurnStart)

        for message in pending:
            emit_message(agent, message, fresh)

        pending = []
        if is_aborted(agent.control):
            return fail_turn(
                agent,
                "Operation aborted",
                StopReason.Aborted,
                fresh
            )

        request.context = agent.context

        if agent.config.prepare_request.is_some():
            request = agent.config.prepare_request.unwrap()(request)
            agent.context = request.context
            agent.config.model = request.model
            agent.config.thinking_level = request.thinking_level

        let llm_messages = match transform(agent.config, agent.context.messages):
            ok(value): value
            error(cause): return fail_turn(
                agent,
                cause.message(),
                StopReason.Failed,
                fresh
            )

        let llm_request = Request(
            Context(
                llm_messages,
                agent.context.tools.clone()
            ),
            request.model,
            request.thinking_level
        )
        let message = response(agent, llm_request)
        fresh.append(message)
        let tool_messages: List[Message] = []

        if (
            message.stop_reason == StopReason.Failed
            or message.stop_reason == StopReason.Aborted
        ):
            dispatch(
                agent,
                Event.TurnEnd(message, tool_messages)
            )
            return error(AgentError.InvalidState(message.error_message))

        let start = fresh.length()
        let results = try execute_batch(agent, message, fresh)

        for item in fresh.drop(start):
            tool_messages.append(item)

        let turn = Turn(
            message,
            tool_messages,
            agent.context,
            fresh.clone()
        )
        var decision = Decision.Default

        if agent.config.finish_turn.is_some():
            decision = agent.config.finish_turn.unwrap()(turn)

        dispatch(
            agent,
            Event.TurnEnd(message, tool_messages)
        )
        previous = some(turn)
        if (
            decision == Decision.End
            or (
                not results.is_empty()
                and results.every(
                    fn(result: ToolResult) -> Bool: result.terminate
                )
            )
        ):
            return ok(unit)
        if is_aborted(agent.control):
            return error(AgentError.InvalidState("Operation aborted"))

        pending = drain(agent.control, true, agent.config.steering_mode)
        if (
            not results.is_empty()
            or not pending.is_empty()
            or decision == Decision.Continue
        ):
            continue

        pending = drain(agent.control, false, agent.config.follow_up_mode)
        if pending.is_empty():
            return ok(unit)

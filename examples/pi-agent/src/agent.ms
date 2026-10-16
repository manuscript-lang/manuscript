import Closeable from "@std/cleanup.ms"
import JsonValue from "@std/json.ms"
import {
    current_system_message,
    system_prompt,
    declaration,
    declare_tool_changes,
    copy_json
} from "./transcript.ms"
import {validate_arguments, validate_output} from "./schema.ms"
import {wall_clock, clock} from "@std/time.ms"
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
    AgentError,
    ToolResultPatch,
    ToolCallOutcome,
    StreamRuntime
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

export fn create_agent(config: Config, context: Context = Context()) -> Agent:
    return new_agent(config, context, true)

fn new_agent(config: Config, context: Context, seed_system: Bool) -> Agent:
    let messages = context.messages.clone()

    if (
        seed_system
        and not context.tools.is_empty
        and (messages.is_empty or messages.first.unwrap().role != Role.System)
    ):
        let baseline = Message(Role.System)

        for tool in context.tools:
            match declaration(tool):
                ok(value): baseline.tools_added.append(value)
                error(_): continue

        messages.prepend(baseline)

    return Agent(config, Context(messages, context.tools.clone()))

# A host shares this default runtime explicitly across agents and loops.
export fn set_default_stream_fn(
    runtime: StreamRuntime,
    stream: Optional[
        fn(
            request: Request,
            control: Synchronized[Control],
            update: fn(message: Message) -> Unit
        ) -> Result[Message, Error]
    ]
) -> Unit:
    runtime.stream = stream

export fn active_signal(agent: Agent) -> Optional[Synchronized[Control]]:
    with guard = agent.control.lock():
        if guard.value.running: return guard.value.signal

        return none

export fn set_tools(agent: Agent, tools: List[Tool]) -> Unit:
    agent.context.tools = tools.clone()

export fn replace_messages(
    agent: Agent,
    messages: List[Message]
) -> Result[Unit, AgentError]:
    if agent.is_streaming: return error(
        AgentError.InvalidState("Cannot replace messages while running")
    )

    agent.context.messages = messages.clone()
    return ok(unit)

export fn append_message(agent: Agent, message: Message) -> Result[Unit, AgentError]:
    if agent.is_streaming: return error(
        AgentError.InvalidState(
            "Cannot append messages while running; use steer or follow_up"
        )
    )

    agent.context.messages.append(message)
    return ok(unit)

export fn get_system_prompt(agent: Agent) -> String:
    return system_prompt(agent.context.messages)

export fn clear_steering_queue(agent: Agent) -> Unit:
    with guard = agent.control.lock(): guard.value.steering = []

export fn clear_follow_up_queue(agent: Agent) -> Unit:
    with guard = agent.control.lock(): guard.value.follow_up = []

export fn clear_all_queues(agent: Agent) -> Unit:
    with guard = agent.control.lock():
        guard.value.steering = []
        guard.value.follow_up = []

export fn has_queued_messages(agent: Agent) -> Bool:
    with guard = agent.control.lock():
        return (not guard.value.steering.is_empty or not guard.value.follow_up.is_empty)

export fn peek_queued_messages(agent: Agent) -> List[Message]:
    with guard = agent.control.lock():
        let state = guard.value

        if not state.steering.is_empty:
            if agent.config.steering_mode == QueueMode.All: return (
                state
                .steering
                .clone()
            )

            return state.steering.take(1)

        if agent.config.follow_up_mode == QueueMode.All: return state.follow_up.clone()

        return state.follow_up.take(1)

# Wait for the run observed on entry, even if an unrelated later run starts.
export fn wait_for_idle(agent: Agent) -> Unit:
    with guard = agent.control.lock():
        if not guard.value.running: return

        let generation = guard.value.generation

        while guard.value.completed_generation < generation:
            guard.wait()

export fn prompt_text(
    agent: Agent,
    text: String,
    images: List[Content] = []
) -> Result[List[Message], Error]:
    for block in images:
        match block:
            Image(_, _): continue
            _: return error(
                AgentError.InvalidState(
                    "prompt_text images must contain image blocks"
                )
            )

    return prompt(
        agent,
        [
            Message(
                Role.User,
                [Content.Text(text)].concat(images),
                timestamp_ms: now_ms()
            )
        ]
    )

export fn prompt_message(agent: Agent, message: Message) -> Result[List[Message], Error]:
    return prompt(agent, [message])

fn now_ms() -> Int:
    let now = wall_clock().now()
    return now.unix_seconds * 1000 + now.nanoseconds / 1000000

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
    return run(new_agent(config, context, false), prompts)

export fn run_agent_loop_continue(
    context: Context,
    config: Config
) -> Result[List[Message], Error]:
    if context.messages.is_empty: return error(
        AgentError.InvalidState("Cannot continue: no messages in context")
    )
    if context.messages.last.unwrap().role == Role.Assistant: return error(
        AgentError.InvalidState("Cannot continue from an assistant message")
    )

    return run(new_agent(config, context, false), [])

export fn abort(agent: Agent) -> Unit:
    let signal = active_signal(agent)
    if signal.is_none: return

    request_abort(signal.unwrap())

export fn steer(agent: Agent, message: Message) -> Unit:
    with guard = agent.control.lock():
        guard.value.steering.append(message)

export fn follow_up(agent: Agent, message: Message) -> Unit:
    with guard = agent.control.lock():
        guard.value.follow_up.append(message)

fn cancellation_control(control: Synchronized[Control]) -> Synchronized[Control]:
    with guard = control.lock():
        return guard.value.signal.unwrap_or(control)

export fn is_aborted(control: Synchronized[Control]) -> Bool:
    with guard = cancellation_control(control).lock(): return guard.value.aborted

# Notify blocked cancellation consumers as well as cooperative callers.
export fn request_abort(control: Synchronized[Control]) -> Unit:
    with guard = cancellation_control(control).lock():
        guard.value.aborted = true
        guard.notify_all()

export fn wait_for_abort(control: Synchronized[Control]) -> Unit:
    with guard = cancellation_control(control).lock():
        while not guard.value.aborted:
            guard.wait()

export fn reset(agent: Agent) -> Result[Unit, AgentError]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Cannot reset a running agent"))

    let baseline = current_system_message(agent.context.messages)
    agent.context.messages = []

    if baseline.is_some: agent.context.messages.append(baseline.unwrap())

    agent.error_message = ""
    agent.streaming_message = none
    agent.pending_tool_calls = []

    with guard = agent.control.lock():
        let previous = guard.value
        guard.set(
            Control(
                generation: previous.generation,
                completed_generation: previous.completed_generation
            )
        )

    return ok(unit)

export fn prompt(agent: Agent, messages: List[Message]) -> Result[List[Message], Error]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Agent is already running"))

    return run(agent, messages)

export fn continue_agent(agent: Agent) -> Result[List[Message], Error]:
    if agent.is_streaming:
        return error(AgentError.InvalidState("Agent is already running"))
    if (
        agent.context.messages.is_empty
        or agent.context.messages.every(
            fn(message: Message) -> Bool: (message.role == Role.System)
        )
    ):
        return error(AgentError.InvalidState("Cannot continue: no messages in context"))

    if agent.context.messages.last.unwrap().role == Role.Assistant:
        let steering = drain(agent.control, true, agent.config.steering_mode)
        if not steering.is_empty: return run(
            agent,
            steering,
            skip_initial_steering: true
        )

        let follow = drain(agent.control, false, agent.config.follow_up_mode)
        if not follow.is_empty: return run(agent, follow)

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
        let state = guard.value
        var queue = state.follow_up

        if steering:
            queue = state.steering

        if queue.is_empty:
            return []

        var count = queue.length

        if mode == QueueMode.OneAtATime:
            count = 1

        let result = queue.take(count)
        queue.splice(0, count, [])
        return result

fn emit_message(agent: Agent, message: Message, fresh: List[Message]) -> Unit:
    agent.context.messages.append(message)
    fresh.append(message)
    dispatch(agent, Event.MessageStart(message))
    dispatch(agent, Event.MessageEnd(message))

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
        .find(fn(tool: Tool) -> Bool: (tool.name == call.name))
    )
    if selected.is_none:
        return error(AgentError.InvalidState("Tool {call.name} not found"))

    let tool = selected.unwrap()
    var raw = try copy_json(call.arguments)

    if tool.prepare_arguments.is_some: raw = try tool.prepare_arguments.unwrap()(raw)

    var arguments = try validate_arguments(tool.parameters, raw, formats: tool.formats)

    if tool.validate.is_some:
        arguments = try tool.validate.unwrap()(arguments)

        if tool.parameters != JsonValue.Null:
            arguments = try validate_output(
                tool.parameters,
                arguments,
                formats: tool.formats
            )

    var control = call.control

    if control.is_none: control = active_signal(agent)

    if control.is_none: control = some(Synchronized(Control()))

    return ok(
        PreparedCall(
            tool,
            ToolCall(
                call.id,
                call.name,
                arguments,
                original_arguments: some(call.arguments),
                assistant_message: call.assistant_message,
                control: control
            )
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

    if is_aborted(tool.call.control.unwrap()):
        return fail_result("Operation aborted")

    if permission.blocked:
        let blocked = fail_result(permission.reason)
        blocked.terminate = permission.terminate
        return blocked

    return finalize(agent, tool.call, execute_tool(agent, tool.tool, tool.call, update))

export fn run_tool_call_outcome(
    agent: Agent,
    call: ToolCall,
    update: fn(result: ToolResult) -> Unit
) -> ToolCallOutcome:
    return ToolCallOutcome(call, run_tool_call(agent, call, update))

fn apply_patch(result: ToolResult, patch: ToolResultPatch) -> ToolResult:
    let changed = result.clone()

    if patch.content.is_some:
        changed.content = patch.content.unwrap()
        changed.structured_content = none

    if patch.structured_content.is_some: changed.structured_content = patch.structured_content

    if patch.details.is_some: changed.details = patch.details.unwrap()

    if patch.is_error.is_some: changed.is_error = patch.is_error.unwrap()

    if patch.terminate.is_some: changed.terminate = patch.terminate.unwrap()

    if patch.usage.is_some: changed.usage = patch.usage

    return changed

fn preflight(agent: Agent, call: ToolCall) -> Result[Preflight, Error]:
    match agent.config.before_tool_call:
        some(hook): return hook(call, agent.context)
        none: return ok(Preflight())

fn finalize(agent: Agent, call: ToolCall, result: ToolResult) -> ToolResult:
    var finalized = result

    if agent.config.after_tool_call.is_some:
        finalized = match agent.config.after_tool_call.unwrap()(
            call,
            finalized,
            agent.context
        ):
            ok(value): value
            error(cause): fail_result(cause.message())

    if agent.config.after_tool_patch.is_some:
        let patch = match agent.config.after_tool_patch.unwrap()(
            call,
            finalized,
            agent.context
        ):
            ok(value): value
            error(cause): return fail_result(cause.message())

        finalized = apply_patch(finalized, patch)

    finalized.duration_ms = result.duration_ms
    return finalized

type UpdateLifetime:
    accepting: Synchronized[Bool]
    closed: Bool = false

impl Closeable for UpdateLifetime:
    fn close() -> Unit:
        if self.closed: return

        with guard = self.accepting.lock(): guard.set(false)

        self.closed = true

fn execute_tool(
    agent: Agent,
    tool: Tool,
    call: ToolCall,
    update: fn(result: ToolResult) -> Unit
) -> ToolResult:
    if is_aborted(call.control.unwrap()):
        return fail_result("Operation aborted")

    with updates = UpdateLifetime(Synchronized(true)):
        let accepting = updates.accepting
        let guarded_update = fn(result: ToolResult) -> Unit:
            with guard = accepting.lock():
                if guard.value:
                    update(result)

        let started = clock().now()

        var result = match tool.execute(call, call.control.unwrap(), guarded_update):
            ok(value): value
            error(cause): fail_result(cause.message())

        result.duration_ms = some(clock().now().difference(started).milliseconds)

        updates.close()

        return result

fn calls_from(message: Message) -> List[ToolCall]:
    let calls: List[ToolCall] = []

    for block in message.content:
        match block:
            ToolCall(id, name, arguments): calls.append(
                ToolCall(
                    id,
                    name,
                    arguments,
                    assistant_message: some(message)
                )
            )
            _: continue

    return calls

fn tool_message(call: ToolCall, result: ToolResult) -> Message:
    return Message(
        Role.ToolResult,
        result.content,
        tool_call_id: call.id,
        tool_name: call.name,
        is_error: result.is_error,
        details: result.details,
        usage: result.usage,
        duration_ms: result.duration_ms,
        timestamp_ms: now_ms()
    )

# The event gate serializes sinks even when tool callbacks run concurrently.
fn execute_batch(
    agent: Agent,
    message: Message,
    fresh: List[Message]
) -> Result[List[ToolResult], Error]:
    let batch = agent.clone()
    batch.context = Context(agent.context.messages.clone(), agent.context.tools.clone())
    let calls = calls_from(message)
    let results: List[ToolResult] = []
    var sequential = agent.config.tool_execution == ExecutionMode.Sequential

    for call in calls:
        let tool = (
            agent
            .context
            .tools
            .find(fn(tool: Tool) -> Bool: (tool.name == call.name))
        )

        if (
            tool.is_some
            and tool.unwrap().execution_mode == some(
                ExecutionMode.Sequential
            )
        ):
            sequential = true

    let gate = Synchronized(agent)

    if sequential or message.stop_reason == StopReason.Length:
        for call in calls:
            agent.pending_tool_calls.append(call.id)
            dispatch(agent, Event.ToolStart(call))
            var result = fail_result(
                "Tool arguments may be truncated; re-issue the call"
            )

            if message.stop_reason != StopReason.Length:
                result = run_tool_call(
                    batch,
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
                .filter(fn(id: String) -> Bool: (id != call.id))
            )
            dispatch(agent, Event.ToolEnd(call, result))
            results.append(result)
            emit_message(agent, tool_message(call, result), fresh)
            if is_aborted(agent.control): break

        agent.pending_tool_calls = []
        return ok(results)

    # Validation and admission run in source order before concurrent execution.
    let prepared: List[Optional[PreparedCall]] = []

    for call in calls:
        agent.pending_tool_calls.append(call.id)
        dispatch(agent, Event.ToolStart(call))
        var tool: Optional[PreparedCall] = none
        var result = fail_result("Tool not found")

        match prepare_tool(batch, call):
            ok(value): tool = some(value)
            error(cause): result = fail_result(cause.message())

        if tool.is_some:
            var permission = Preflight()

            match preflight(batch, tool.unwrap().call):
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

                        if tool.is_some:
                            result = execute_tool(
                                batch,
                                tool.unwrap().tool,
                                tool.unwrap().call,
                                fn(
                                    result: ToolResult
                                ) -> Unit:
                                    with guard = gate.lock():
                                        dispatch(
                                            guard.value,
                                            Event.ToolUpdate(
                                                call,
                                                result
                                            )
                                        )
                            )

                        with guard = gate.lock():
                            if tool.is_some:
                                result = finalize(batch, tool.unwrap().call, result)

                            guard.value.pending_tool_calls = (
                                guard
                                .value
                                .pending_tool_calls
                                .filter(
                                    fn(
                                        id: String
                                    ) -> Bool: (id != call.id)
                                )
                            )
                            dispatch(guard.value, Event.ToolEnd(call, result))

                        return result
                )
            )

        let _joined = try tasks.join()

        for entry in handles.entries():
            results.set(entry.index, try entry.value.join())

    agent.pending_tool_calls = []

    for entry in calls.entries():
        emit_message(
            agent,
            tool_message(entry.value, results[entry.index].unwrap()),
            fresh
        )

    return ok(results)

fn transform(config: Config, messages: List[Message]) -> Result[List[Message], Error]:
    var result = messages.clone()

    if config.transform_context.is_some:
        result = try config.transform_context.unwrap()(result)

    if config.convert_to_llm.is_some:
        result = try config.convert_to_llm.unwrap()(result)

    return ok(result)

fn response(agent: Agent, request: Request) -> Message:
    let partial = Message(Role.Assistant)
    let index = agent.context.messages.length
    agent.context.messages.append(partial)
    agent.streaming_message = some(partial)
    dispatch(agent, Event.MessageStart(partial))

    with updates = UpdateLifetime(Synchronized(true)):
        let accepting = updates.accepting
        let update = fn(message: Message) -> Unit:
            with guard = accepting.lock():
                if guard.value:
                    agent.streaming_message = some(message)
                    agent.context.messages.set(index, message)
                    dispatch(agent, Event.MessageUpdate(message))

        let provider_event = request.provider_event
        request.provider_event = some(
            fn(event: JsonValue) -> Unit:
                with guard = accepting.lock():
                    if not guard.value: return

                    if provider_event.is_some: provider_event.unwrap()(event)

                    dispatch(agent, Event.ProviderUpdate(event))
        )
        var stream = agent.config.stream

        if stream.is_none: stream = agent.config.runtime.stream

        var outcome: Result[Message, Error] = error(
            AgentError.InvalidState("No default stream function configured")
        )

        if stream.is_some: outcome = stream.unwrap()(
            request,
            active_signal(agent).unwrap(),
            update
        )

        var result = match outcome:
            ok(value): value
            error(cause): Message(
                Role.Assistant,
                stop_reason: StopReason.Failed,
                error_message: cause.message()
            )

        updates.close()

        if is_aborted(agent.control):
            result.stop_reason = StopReason.Aborted
            result.error_message = "Operation aborted"

        if result.role != Role.Assistant:
            result = Message(
                Role.Assistant,
                stop_reason: StopReason.Failed,
                error_message: "Provider returned a non-assistant message"
            )

        if result.timestamp_ms == 0: result.timestamp_ms = now_ms()

        result.thinking_level = request.thinking_level

        if result.model == "": result.model = request.model

        if result.provider == "": result.provider = agent.config.provider

        agent.context.messages.set(index, result)
        agent.streaming_message = none
        dispatch(agent, Event.MessageEnd(result))
        return result

type RunSettlement:
    agent: Agent

impl Closeable for RunSettlement:
    fn close() -> Unit:
        self.agent.streaming_message = none
        self.agent.pending_tool_calls = []
        self.agent.is_streaming = false

        with guard = self.agent.control.lock():
            guard.value.running = false
            guard.value.completed_generation = guard.value.generation
            guard.notify_all()

fn run(
    agent: Agent,
    prompts: List[Message],
    skip_initial_steering: Bool = false
) -> Result[List[Message], Error]:
    with guard = agent.control.lock():
        let state = guard.value
        if state.running: return error(
            AgentError.InvalidState("Agent is already running")
        )

        state.running = true
        state.generation = state.generation + 1
        state.aborted = false
        state.signal = some(Synchronized(Control()))

    with _settlement = RunSettlement(agent):
        agent.is_streaming = true
        agent.error_message = ""

        let fresh: List[Message] = []
        dispatch(agent, Event.AgentStart)
        let outcome = run_turns(agent, prompts, fresh, skip_initial_steering)
        agent.streaming_message = none
        agent.pending_tool_calls = []

        match outcome:
            ok(_): agent.error_message = ""
            error(cause): agent.error_message = cause.message()

        # Listeners settle before the agent becomes idle.
        dispatch(agent, Event.AgentEnd(fresh.clone()))
        let _completed = try outcome
        return ok(fresh)

fn fail_turn(
    agent: Agent,
    message: String,
    reason: StopReason,
    fresh: List[Message]
) -> Result[Unit, Error]:
    let failed = Message(
        Role.Assistant,
        stop_reason: reason,
        error_message: message,
        timestamp_ms: now_ms(),
        model: (agent.config.model),
        provider: (agent.config.provider),
        thinking_level: (agent.config.thinking_level)
    )
    emit_message(agent, failed, fresh)

    if agent.config.finish_turn.is_some:
        let _decision = (
            agent
            .config
            .finish_turn
            .unwrap()(Turn(failed, [], agent.context, fresh.clone()))
        )

    dispatch(agent, Event.TurnEnd(failed, []))
    return error(AgentError.InvalidState(message))

fn run_turns(
    agent: Agent,
    prompts: List[Message],
    fresh: List[Message],
    skip_initial_steering: Bool
) -> Result[Unit, Error]:
    var pending = prompts.clone()

    var request = Request(
        agent.context,
        agent.config.model,
        agent.config.thinking_level
    )
    var previous: Optional[Turn] = none

    while true:
        var prepared: List[Message] = []

        if previous.is_some and agent.config.prepare_next_turn.is_some:
            request = agent.config.prepare_next_turn.unwrap()(previous.unwrap())
            agent.context = request.context
            agent.config.model = request.model
            agent.config.thinking_level = request.thinking_level
            prepared = request.messages.clone()
            request.messages = []

        if previous.is_some and pending.is_empty:
            pending = drain(agent.control, true, agent.config.steering_mode)

        pending = match declare_tool_changes(
            agent.context.messages,
            prepared.concat(pending),
            (agent.context.tools)
        ):
            ok(value): value
            error(cause):
                dispatch(agent, Event.TurnStart)
                return fail_turn(agent, cause.message(), StopReason.Failed, fresh)

        dispatch(agent, Event.TurnStart)

        for message in pending:
            emit_message(agent, message, fresh)

        pending = []

        if previous.is_none and not skip_initial_steering:
            let initial = drain(agent.control, true, agent.config.steering_mode)

            let announced = match declare_tool_changes(
                agent.context.messages,
                initial,
                (agent.context.tools)
            ):
                ok(value): value
                error(cause): return fail_turn(
                    agent,
                    cause.message(),
                    StopReason.Failed,
                    fresh
                )

            for message in announced: emit_message(agent, message, fresh)

        if is_aborted(agent.control):
            return fail_turn(agent, "Operation aborted", StopReason.Aborted, fresh)

        request.context = agent.context

        if agent.config.prepare_request.is_some:
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

        let options = match request_options(agent):
            ok(value): value
            error(cause): return fail_turn(
                agent,
                cause.message(),
                StopReason.Failed,
                fresh
            )

        let llm_request = Request(
            Context(llm_messages, agent.context.tools.clone()),
            request.model,
            request.thinking_level,
            options: options,
            model_descriptor: agent.config.model_descriptor,
            on_payload: agent.config.on_payload,
            on_response: agent.config.on_response,
            provider_event: agent.config.provider_event
        )
        let message = response(agent, llm_request)
        fresh.append(message)
        let tool_messages: List[Message] = []

        if (
            message.stop_reason == StopReason.Failed
            or message.stop_reason == StopReason.Aborted
        ):
            if agent.config.finish_turn.is_some:
                let _decision = (
                    agent
                    .config
                    .finish_turn
                    .unwrap()(
                        Turn(
                            message,
                            tool_messages,
                            agent.context,
                            fresh.clone()
                        )
                    )
                )

            dispatch(agent, Event.TurnEnd(message, tool_messages))
            return error(AgentError.InvalidState(message.error_message))

        let start = fresh.length
        let results = try execute_batch(agent, message, fresh)

        for item in fresh.drop(start):
            tool_messages.append(item)

        let turn = Turn(message, tool_messages, agent.context, fresh.clone())
        var decision = Decision.Default

        if agent.config.finish_turn.is_some:
            decision = agent.config.finish_turn.unwrap()(turn)

        dispatch(agent, Event.TurnEnd(message, tool_messages))
        previous = some(turn)
        if decision == Decision.End: return ok(unit)
        if is_aborted(agent.control):
            return error(AgentError.InvalidState("Operation aborted"))

        pending = drain(agent.control, true, agent.config.steering_mode)
        if (
            (
                not results.is_empty
                and not results.every(
                    fn(result: ToolResult) -> Bool: result.terminate
                )
            )
            or not pending.is_empty
        ):
            continue

        pending = drain(agent.control, false, agent.config.follow_up_mode)
        if not pending.is_empty: continue
        if decision == Decision.Continue: continue

        return ok(unit)

fn request_options(agent: Agent) -> Result[JsonValue, Error]:
    let options = match agent.config.options:
        ObjectValue(values): values.clone()
        _: Map[String, JsonValue]()

    var key = agent.config.api_key

    if agent.config.get_api_key.is_some:
        let resolved = try agent.config.get_api_key.unwrap()(agent.config.provider)

        if resolved != "": key = resolved

    if key != "": options.add("apiKey", JsonValue.StringValue(key))

    return ok(JsonValue.ObjectValue(options))

import {
    Message,
    Role,
    Content,
    Tool,
    ToolDeclaration
} from "./types.ms"
import {stringify, parse, JsonValue} from "@std/json.ms"

export fn copy_json(value: JsonValue) -> Result[JsonValue, Error]:
    return parse(try stringify(value))

export fn declaration(tool: Tool) -> Result[ToolDeclaration, Error]:
    return ok(
        ToolDeclaration(
            tool.name,
            tool.description,
            try copy_json(tool.parameters),
            tool.constrained_sampling
        )
    )

export fn current_tools(messages: List[Message]) -> List[ToolDeclaration]:
    let tools = Map[String, ToolDeclaration]()

    for message in messages:
        if message.role != Role.System: continue

        for name in message.tools_removed: tools.remove(name)

        for tool in message.tools_added: tools.add(tool.name, tool)

    return tools.values()

export fn current_system_message(messages: List[Message]) -> Optional[Message]:
    let texts: List[String] = []
    let sections = Map[String, Optional[String]]()
    var head: Optional[Message] = none

    for message in messages:
        if message.role != Role.System: continue

        if head.is_none: head = some(message)

        let text = content_text(message.content)

        if text != "": texts.append(text)

        for section in message.sections.entries():
            if section.value.is_none: sections.remove(section.key)
            else: sections.add(section.key, section.value)

    if head.is_none: return none

    let combined = Message(
        Role.System,
        content: [Content.Text(texts.join("\n\n"))],
        timestamp_ms: (head.unwrap().timestamp_ms),
        sections: sections,
        tools_added: current_tools(messages)
    )
    return some(combined)

export fn system_prompt(messages: List[Message]) -> String:
    let baseline = current_system_message(messages)
    if baseline.is_none: return ""

    let system = baseline.unwrap()
    let texts = [content_text(system.content)]

    for section in system.sections.values():
        if section.is_some: texts.append(section.unwrap())

    return texts.filter(fn(text: String) -> Bool: text != "").join("\n\n")

export fn content_text(content: List[Content], separator: String = "\n") -> String:
    let texts: List[String] = []

    for block in content:
        match block:
            Text(text): texts.append(text)
            _: continue

    return texts.join(separator)

export fn collapse_system_messages(messages: List[Message]) -> List[Message]:
    let result: List[Message] = []
    let system = current_system_message(messages)

    if system.is_some: result.append(system.unwrap())

    return result.concat(
        messages.filter(
            fn(message: Message) -> Bool: (message.role != Role.System)
        )
    )

# Override the last pending system message's tool intent with executable reality.
export fn declare_tool_changes(
    history: List[Message],
    pending: List[Message],
    tools: List[Tool]
) -> Result[List[Message], Error]:
    let staged = pending.clone()
    var system_index = -1

    for entry in staged.entries():
        if entry.value.role == Role.System: system_index = entry.index

    if system_index >= 0:
        let system = staged[system_index].unwrap().clone()
        system.tools_added = []
        system.tools_removed = []
        staged.set(system_index, system)

    let old = current_tools(history.concat(staged))
    let current: List[ToolDeclaration] = []

    for tool in tools: current.append(try declaration(tool))

    let added: List[ToolDeclaration] = []
    let removed: List[String] = []

    for previous in old:
        let next = current.find(
            fn(tool: ToolDeclaration) -> Bool: (tool.name == previous.name)
        )

        if next.is_none or next.unwrap() != previous: removed.append(previous.name)

    for next in current:
        let previous = old.find(
            fn(tool: ToolDeclaration) -> Bool: (tool.name == next.name)
        )

        if previous.is_none or previous.unwrap() != next: added.append(next)

    if system_index >= 0:
        let system = staged[system_index].unwrap()
        system.tools_added = added
        system.tools_removed = removed
        return ok(staged)

    if added.is_empty and removed.is_empty: return ok(staged)

    let update = Message(Role.System, tools_added: added, tools_removed: removed)
    var index = staged.length

    for entry in staged.entries():
        if entry.value.role != Role.System:
            index = entry.index
            break

    staged.insert(index, update)
    return ok(staged)

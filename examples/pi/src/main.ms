import (
	Command, Flag, FlagKind, Arg, Matches from "@std/cli/command.ms",
	arguments, environment from "@std/os/env.ms",
	stdin from "@std/io/io.ms",
	lines, read_all from "@std/io/streams.ms",
	read_file from "@std/os/fs.ms",
	base64_encode from "@std/data/encoding.ms",
	JsonValue, parse from "@std/data/json.ms",
	cancel_switch from "@std/concurrency/promise.ms",
	ProviderConfig from "./provider.ms",
	Agent from "./agent.ms",
	Ui from "./ui.ms",
	all_tool_names from "./tools.ms",
	build from "./prompt.ms",
	create, latest, entries, branch, last_id, tree, open_existing, Session from "./session.ms",
	write_out, write_err, bold, dim, red, read_line, is_interactive, with_abort from "./tui.ms",
	terminal_ui, TerminalUi, PlainUi, JsonUi, emit_response from "./frontends.ms",
	str, num, flag, obj, arr, str_or from "./jsonx.ms",
)

version := "0.2.0"

fn first_env(names: List[String]) String:
	env := environment().get(Map[String, String]())
	for name in names:
		if value := env.get(name):
			if not value.is_empty(): return value.clone()
	return ""

// Thinking budget in tokens from "off", "low", "medium", "high" or a number.
fn thinking_budget(level: String) Int!:
	if level.is_empty() or level == "off": return ok(0)
	if level == "minimal": return ok(1024)
	if level == "low": return ok(2048)
	if level == "medium": return ok(8192)
	if level == "high": return ok(16384)
	if n := level.parse_int(): return ok(n)

	return error(
		Error(
			"Unknown thinking level {level}; use off, minimal, low, medium, high or a token count"
		)
	)

fn provider_config(m: Matches) ProviderConfig!:
	api := m.string("provider")
	if api != "anthropic" and api != "openai": return error(
		Error("Unknown provider {api}; use anthropic or openai")
	)

	anthropic := api == "anthropic"
	key := if m.string("api-key").is_empty(): first_env(
		if anthropic: ["ANTHROPIC_API_KEY"] else: ["OPENAI_API_KEY"]
	) else: m.string("api-key")
	if key.is_empty(): return error(
		Error(
			"No API key: pass --api-key or set {if anthropic: "ANTHROPIC_API_KEY" else: "OPENAI_API_KEY"}"
		)
	)

	base := if not m.string("base-url").is_empty(): m.string("base-url") else: first_env(
		if anthropic: ["ANTHROPIC_BASE_URL"] else: ["OPENAI_BASE_URL"]
	)
	url := if base.is_empty(): (
		if anthropic: "https://api.anthropic.com" else: "https://api.openai.com/v1"
	) else: base
	model := if m.string("model").is_empty(): (
		if anthropic: "claude-sonnet-4-5" else: "gpt-4o"
	) else: m.string("model")
	return ok(
		ProviderConfig(
			api: api, base_url: url.trim_end_chars("/"), api_key: key, model: model,
			thinking: try thinking_budget(m.string("thinking"))
		)
	)

fn enabled_tools(m: Matches) List[String]!:
	if m.bool("no-tools"): return ok(List[String]())

	spec := m.string("tools")
	if spec.is_empty(): return ok(["read", "bash", "edit", "write"])

	names := spec.split(",").map(fn t: t.trim())
	for name in names:
		if not all_tool_names().contains(name): return error(
			Error(
				"Unknown tool {name}; available: {all_tool_names().join(", ")}"
			)
		)
	return ok(names)

// A prompt after `@file` expansion: text files become <file> blocks, images become image blocks.
type Prompt:
	text: String
	images: List[JsonValue]

fn media_type(path: String) String?:
	lower := path.lower()
	if lower.ends_with(".png"): return "image/png"
	if lower.ends_with(".jpg") or lower.ends_with(".jpeg"): return "image/jpeg"
	if lower.ends_with(".gif"): return "image/gif"
	if lower.ends_with(".webp"): return "image/webp"

	return none

fn image_block(kind: String, data: String) JsonValue:
	var source = Map[String, JsonValue]()
	source.add("type", str("base64"))
	source.add("media_type", str(kind))
	source.add("data", str(data))

	var block = Map[String, JsonValue]()
	block.add("type", str("image"))
	block.add("source", obj(source))
	return obj(block)

fn expand_message(words: List[String]) Prompt!:
	var parts = List[String]()
	var images = List[JsonValue]()

	for word in words:
		path := word.cut_prefix("@")

		if path.is_none():
			parts.append(word.clone())
			continue

		file := path.get("")
		data := try read_file(file).wait()
		kind := media_type(file)

		if kind.is_some():
			images.append(image_block(kind.get(""), base64_encode(data)))
			continue

		parts.append("<file name=\"{file}\">\n{data.decode_utf8().get("")}\n</file>")

	return ok(Prompt(text: parts.join(" "), images: images))

fn open_session(m: Matches) Session?!:
	if m.bool("no-session"): return ok(none)
	if path := m.string_or_none("session"): return ok(try open_existing(path))

	if m.bool("continue"):
		if path := latest(): return ok(try open_existing(path))
	return ok(try create())

fn session_label(agent: Agent) String:
	if saved := agent.session: return saved.path.clone()

	return "(not saved)"

fn help_text() String:
	return "/help             this list\n/exit             leave pi\n/session          path of the session file\n/tools            enabled tools\n/usage            tokens used so far\n/model <id>       switch model\n/thinking <level> off, low, medium, high or a token count\n/compact [focus]  summarize the conversation to free context\n/tree             list session entries; * marks the active one\n/fork <id>        continue from an earlier entry as a new branch\n/new              start a fresh session\nEsc or Ctrl-C     abort the running turn\nAlt-Enter         insert a newline\nTab               complete a slash command\n"

fn run_turn(var agent: Agent, text: String, images: List[JsonValue], var ui: Ui) Unit:
	result := with_abort(fn stop: agent.prompt(text, images, var ui, stop))
	ui.end()

	if result.is_error():
		if result.err().kind == "ECANCELED":
			write_err(dim("(aborted)\n"))
		else:
			write_err(red("error: {result.err().message}\n"))

fn run_compact(var agent: Agent, focus: String) Unit:
	write_out(dim("compacting…\n"))

	result := with_abort(fn stop: agent.compact(focus, stop))

	if result.is_error():
		write_err(red("compact failed: {result.err().message}\n"))
		return

	write_out(dim("compacted; history is now one summary message\n"))

// Runs a slash command. Returns true when pi should exit.
fn slash(var agent: Agent, line: String) Bool:
	parts := line.split(" ", 2)
	command := parts[0].clone()
	arg := parts.get(1, "").trim()
	if command == "/exit" or command == "/quit": return true

	if command == "/help": write_out(help_text())
	else if command == "/session": write_out("{session_label(agent)}\n")
	else if command == "/tools": write_out("{agent.tools.join(", ")}\n")
	else if command == "/usage": write_out(
		"input {agent.input_tokens} tokens, output {agent.output_tokens} tokens\n"
	)
	else if command == "/model": switch_model(var agent, arg)
	else if command == "/thinking": switch_thinking(var agent, arg)
	else if command == "/compact": run_compact(var agent, arg)
	else if command == "/tree": show_tree(agent)
	else if command == "/fork": fork_to(var agent, arg)
	else if command == "/new": new_session(var agent)
	else: write_out("Unknown command {command}; try /help\n")

	return false

fn switch_model(var agent: Agent, name: String) Unit:
	if name.is_empty():
		write_out("{agent.config.model}\n")
		return

	agent.config.model = name.clone()
	write_out("model: {name}\n")

fn switch_thinking(var agent: Agent, level: String) Unit:
	budget := thinking_budget(level)

	if budget.is_error():
		write_err(red("{budget.err().message}\n"))
		return

	agent.config.thinking = budget.get(0)
	write_out("thinking budget: {agent.config.thinking} tokens\n")

fn show_tree(agent: Agent) Unit:
	saved := agent.session

	if saved.is_none():
		write_out("Sessions are off (--no-session)\n")
		return

	all := entries(saved.get(none).path)

	if all.is_error():
		write_err(red("{all.err().message}\n"))
		return

	write_out("{tree(all.get([]), agent.leaf).join("\n")}\n")

fn fork_to(var agent: Agent, id: String) Unit:
	if id.is_empty():
		write_out("usage: /fork <entry id>; see /tree\n")
		return

	result := agent.fork(id)

	if result.is_error():
		write_err(red("{result.err().message}\n"))
		return

	write_out("branch moved to {id}; the next message continues from there\n")

fn new_session(var agent: Agent) Unit:
	if agent.session.is_some():
		fresh := create()

		if fresh.is_error():
			write_err(red("{fresh.err().message}\n"))
			return

		agent.session = fresh.get(none)

	agent.history = List[JsonValue]()
	agent.leaf = ""
	write_out("new session\n")

fn interactive(var agent: Agent) Unit!:
	write_out(
		"{bold("pi")} {version} · {agent.config.model} · /help for commands, Ctrl-D to exit\n"
	)

	var history = List[String]()
	var ui: Ui = terminal_ui()

	while true:
		line := try read_line("{bold("> ")}", history)
		if line.is_none(): break

		text := line.get("").trim()
		if text.is_empty(): continue

		history.append(text.clone())

		if text.starts_with("/"):
			if slash(var agent, text): break

			continue

		run_turn(var agent, text, List[JsonValue](), var ui)

// JSON-lines RPC: one command object per stdin line, events and responses on stdout.
fn rpc(var agent: Agent) Unit!:
	var input = lines(stdin())
	var ui: Ui = JsonUi(unused: true)

	for raw in input:
		if raw.trim().is_empty(): continue

		command := parse(raw)

		if command.is_error():
			var f = Map[String, JsonValue]()
			f.add("error", str(command.err().message))
			emit_response("parse", false, f)
			continue

		doc := command.get(none)
		kind := str_or(doc, "type", "")
		var f = Map[String, JsonValue]()

		if kind == "prompt":
			stop := cancel_switch()
			result := agent.prompt(
				str_or(doc, "message", ""), List[JsonValue](), var ui, stop.signal()
			)
			ui.end()

			if result.is_error():
				f.add("error", str(result.err().message))
			else:
				f.add("text", str(result.get("")))

			f.add("inputTokens", num(agent.input_tokens))
			f.add("outputTokens", num(agent.output_tokens))
			emit_response(kind, result.is_ok(), f)
		else if kind == "compact":
			stop := cancel_switch()
			result := agent.compact(str_or(doc, "focus", ""), stop.signal())

			if result.is_ok(): f.add("summary", str(result.get("")))
			else: f.add("error", str(result.err().message))

			emit_response(kind, result.is_ok(), f)
		else if kind == "fork":
			result := agent.fork(str_or(doc, "id", ""))
			if result.is_error(): f.add("error", str(result.err().message))
			emit_response(kind, result.is_ok(), f)
		else if kind == "get_state":
			f.add("model", str(agent.config.model))
			f.add("messages", num(agent.history.length()))
			f.add("session", str(session_label(agent)))
			f.add("leaf", str(agent.leaf))
			emit_response(kind, true, f)
		else if kind == "get_messages":
			f.add("messages", arr(agent.history.clone()))
			emit_response(kind, true, f)
		else if kind == "exit":
			emit_response(kind, true, f)
			break
		else:
			f.add("error", str("Unknown command {kind}"))
			emit_response(kind, false, f)

fn run(m: Matches) Int!:
	config := try provider_config(m)
	tools := try enabled_tools(m)
	custom: String? = if m.string("system-prompt").is_empty(): none else: m.string(
		"system-prompt"
	)
	system := build(tools, custom, m.string("append-system-prompt"))
	session := try open_session(m)
	var history = List[JsonValue]()
	var leaf = ""

	if saved := session:
		if m.bool("continue") or m.string_or_none("session").is_some():
			all := try entries(saved.path)
			leaf = last_id(all)
			history = branch(all, leaf)

	var agent = Agent(
		config: config, system: system, tools: tools, history: history,
		session: session, leaf: leaf, input_tokens: 0, output_tokens: 0
	)
	mode := m.string("mode")

	if mode == "rpc":
		try rpc(var agent)
		return ok(0)

	prompt := try expand_message(m.list("message"))
	var text = prompt.text.clone()
	piped := not is_interactive()

	if piped and (not text.is_empty() or m.bool("print") or mode == "json"):
		data := try read_all(stdin(), 16777216)
		extra := data.decode_utf8().get("")
		if not extra.is_empty(): text = "{extra}\n{text}"

	if mode == "json":
		if text.trim().is_empty(): return error(Error("No prompt given"))

		var ui: Ui = JsonUi(unused: true)
		stop := cancel_switch()
		_reply := try agent.prompt(text, prompt.images, var ui, stop.signal())
		ui.end()
		return ok(0)

	if m.bool("print") or piped:
		if text.trim().is_empty(): return error(Error("No prompt given"))

		var ui: Ui = PlainUi(unused: true)
		stop := cancel_switch()
		_reply := try agent.prompt(text, prompt.images, var ui, stop.signal())
		ui.end()
		return ok(0)

	if not text.is_empty():
		var ui: Ui = terminal_ui()
		run_turn(var agent, text, prompt.images, var ui)

	try interactive(var agent)
	return ok(0)

fn main() Int:
	pi := Command(
		name: "pi",
		about: "A minimal AI coding agent: chat with an LLM that can read, write, edit and run code.",
		flags: [
			Flag(
				"print", FlagKind.Bool, "p",
				help: "Non-interactive: run the prompt, print the reply, exit"
			),
			Flag(
				"mode", FlagKind.String, default: "text",
				choices: ["text", "json", "rpc"],
				help: "Output mode: text, json (event lines) or rpc (JSON commands on stdin)"
			),
			Flag(
				"continue", FlagKind.Bool, "c", help: "Continue the previous session"
			),
			Flag("session", FlagKind.String, help: "Use this session file"),
			Flag(
				"no-session", FlagKind.Bool, help: "Do not save the conversation"
			),
			Flag(
				"provider", FlagKind.String, default: "anthropic",
				help: "anthropic or openai"
			),
			Flag(
				"model", FlagKind.String, "m", default: "", help: "Model id"
			),
			Flag(
				"thinking", FlagKind.String, default: "off",
				help: "Reasoning effort: off, minimal, low, medium, high or a token budget"
			),
			Flag(
				"api-key", FlagKind.String, default: "",
				help: "API key (defaults to the provider's environment variable)"
			),
			Flag(
				"base-url", FlagKind.String, default: "",
				help: "Override the API base URL"
			),
			Flag(
				"system-prompt", FlagKind.String, default: "",
				help: "Replace the system prompt"
			),
			Flag(
				"append-system-prompt", FlagKind.String, default: "",
				help: "Append to the system prompt"
			),
			Flag(
				"tools", FlagKind.String, default: "",
				help: "Comma-separated tools to enable (read,bash,edit,write,grep,find,ls)"
			),
			Flag("no-tools", FlagKind.Bool, help: "Disable all tools")
		],
		args: [
			Arg(
				"message", help: "Prompt; @path includes a file or image",
				required: false, rest: true
			)
		],
		exec: fn m: run(m)
	)
	return pi.execute(arguments())

import (
	Command, Flag, FlagKind, Arg, Matches from "@std/cli/command.ms",
	arguments, environment from "@std/os/env.ms",
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
	read_file from "@std/os/fs.ms",
	JsonValue from "@std/data/json.ms",
	ProviderConfig from "./provider.ms",
	Agent, Events from "./agent.ms",
	all_tool_names from "./tools.ms",
	build from "./prompt.ms",
	create, latest, load, open_existing, Session from "./session.ms",
	write_out, write_err, bold, dim, red, read_line, is_interactive from "./tui.ms",
)

version := "0.1.0"

fn first_env(names: List[String]) String:
	env := environment().get(Map[String, String]())
	for name in names:
		if value := env.get(name):
			if not value.is_empty(): return value.clone()
	return ""

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
			api: api, base_url: url.trim_end_chars("/"), api_key: key, model: model
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

// Expands @path words into the file's contents, as pi does.
fn expand_message(words: List[String]) String!:
	var parts = List[String]()

	for word in words:
		if path := word.cut_prefix("@"):
			data := try read_file(path).wait()
			parts.append(
				"<file name=\"{path}\">\n{data.decode_utf8().get("")}\n</file>"
			)
		else:
			parts.append(word.clone())

	return ok(parts.join(" "))

fn open_session(m: Matches) Session?!:
	if m.bool("no-session"): return ok(none)
	if path := m.string_or_none("session"): return ok(try open_existing(path))

	if m.bool("continue"):
		if path := latest(): return ok(try open_existing(path))
	return ok(try create())

fn show_events(verbose: Bool) Events:
	return Events(
		on_text: fn text: write_out(text),
		on_tool: fn(name: String, summary: String): write_err(
			dim("\n▸ {name} {summary}\n")
		),
		on_result: fn(name: String, failed: Bool, text: String): show_result(
			verbose, failed, text
		)
	)

fn show_result(verbose: Bool, failed: Bool, text: String) Unit:
	if failed: write_err(red("{text.take(400)}\n"))
	else if verbose: write_err(dim("{text.take(400)}\n"))

fn session_label(agent: Agent) String:
	if saved := agent.session: return saved.path.clone()

	return "(not saved)"

fn slash(agent: Agent, line: String) Bool:
	if line == "/exit" or line == "/quit": return true

	if line == "/help":
		write_out("/help  /exit  /session  /tools  /usage\n")
	else if line == "/session":
		write_out("{session_label(agent)}\n")
	else if line == "/tools":
		write_out("{agent.tools.join(", ")}\n")
	else if line == "/usage":
		write_out(
			"input {agent.input_tokens} tokens, output {agent.output_tokens} tokens\n"
		)
	else:
		write_out("Unknown command {line}; try /help\n")

	return false

fn interactive(var agent: Agent) Unit!:
	write_out(
		"{bold("pi")} {version} · {agent.config.model} · /help for commands, Ctrl-D to exit\n"
	)

	var history = List[String]()
	events := show_events(false)

	while true:
		line := try read_line("{bold("> ")}", history)
		if line.is_none(): break

		text := line.get("").trim()
		if text.is_empty(): continue

		history.append(text.clone())

		if text.starts_with("/"):
			if slash(agent, text): break

			continue

		reply := agent.prompt(text, events)
		if reply.is_error(): write_err(red("\nerror: {reply.err().message}\n"))
		write_out("\n")

fn run(m: Matches) Int!:
	config := try provider_config(m)
	tools := try enabled_tools(m)
	custom: String? = if m.string("system-prompt").is_empty(): none else: m.string(
		"system-prompt"
	)
	system := build(tools, custom, m.string("append-system-prompt"))
	session := try open_session(m)
	var history = List[JsonValue]()
	if saved := session:
		if m.bool("continue") or m.string_or_none("session").is_some(): history = try load(
			saved.path
		)

	var agent = Agent(
		config: config, system: system, tools: tools, history: history,
		session: session, input_tokens: 0, output_tokens: 0
	)
	var prompt_text = try expand_message(m.list("message"))
	piped := not is_interactive()

	if piped and not prompt_text.is_empty() or piped and m.bool("print"):
		data := try read_all(stdin(), 16777216)
		extra := data.decode_utf8().get("")
		if not extra.is_empty(): prompt_text = "{extra}\n{prompt_text}"

	if m.bool("print") or piped:
		if prompt_text.trim().is_empty(): return error(Error("No prompt given"))

		events := show_events(false)
		_reply := try agent.prompt(prompt_text, events)
		write_out("\n")
		return ok(0)

	if not prompt_text.is_empty():
		events := show_events(false)
		_reply := try agent.prompt(prompt_text, events)
		write_out("\n")

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
				"message", help: "Prompt; @path includes a file", required: false,
				rest: true
			)
		],
		exec: fn m: run(m)
	)
	return pi.execute(arguments())

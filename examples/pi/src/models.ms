// Provider and model registry: built-in providers, custom ones from ~/.pi/agent/models.json (pi's format),
// and API keys from the environment or ~/.pi/agent/auth.json.
import (
	JsonValue, parse from "@std/data/json.ms",
	read_file, write_file, create_directory from "@std/os/fs.ms",
	environment, home_directory from "@std/os/env.ms",
	join from "@std/os/path.ms",
	str, obj, render, str_or from "./jsonx.ms",
)

export type Provider:
	name: String
	// Wire format: "anthropic" or "openai" (chat completions).
	api: String
	base_url: String
	// Environment variables checked for a key, in order.
	key_env: List[String]
	default_model: String
	models: List[String]
	// A key written in models.json, used when nothing else is set.
	key: String
	// True when no key is needed (local servers).
	keyless: Bool

fn builtin(
	name: String,
	api: String,
	base: String,
	env: List[String],
	default_model: String,
	models: List[String],
	keyless: Bool
) Provider:
	return Provider(
		name: name, api: api, base_url: base, key_env: env,
		default_model: default_model, models: models, key: "", keyless: keyless
	)

export fn builtin_providers() List[Provider]:
	return [
		builtin(
			"anthropic", "anthropic", "https://api.anthropic.com",
			["ANTHROPIC_API_KEY"], "claude-sonnet-4-5",
			["claude-opus-4-1", "claude-sonnet-4-5", "claude-haiku-4-5"], false
		),
		builtin(
			"openai", "openai", "https://api.openai.com/v1", ["OPENAI_API_KEY"],
			"gpt-4o", ["gpt-4o", "gpt-4o-mini", "o3-mini"], false
		),
		builtin(
			"openrouter", "openai", "https://openrouter.ai/api/v1",
			["OPENROUTER_API_KEY"], "anthropic/claude-sonnet-4.5",
			["anthropic/claude-sonnet-4.5", "openai/gpt-4o"], false
		),
		builtin(
			"groq", "openai", "https://api.groq.com/openai/v1", ["GROQ_API_KEY"],
			"llama-3.3-70b-versatile", ["llama-3.3-70b-versatile"], false
		),
		builtin(
			"xai", "openai", "https://api.x.ai/v1", ["XAI_API_KEY"], "grok-4",
			["grok-4"], false
		),
		builtin(
			"mistral", "openai", "https://api.mistral.ai/v1", ["MISTRAL_API_KEY"],
			"mistral-large-latest", ["mistral-large-latest"], false
		),
		builtin(
			"cerebras", "openai", "https://api.cerebras.ai/v1", ["CEREBRAS_API_KEY"],
			"gpt-oss-120b", ["gpt-oss-120b"], false
		),
		builtin(
			"gemini", "openai",
			"https://generativelanguage.googleapis.com/v1beta/openai",
			["GEMINI_API_KEY", "GOOGLE_API_KEY"], "gemini-2.5-pro",
			["gemini-2.5-pro", "gemini-2.5-flash"], false
		),
		builtin(
			"ollama", "openai", "http://localhost:11434/v1", ["OLLAMA_API_KEY"],
			"llama3.2", ["llama3.2"], true
		)
	]

fn config_dir() String:
	home := home_directory().get("")
	return join([home, ".pi", "agent"])

fn read_json(name: String) JsonValue?:
	data := read_file(join([config_dir(), name]), 1048576).wait().to_optional()
	if data.is_none(): return none

	text := data.get("".to_bytes()).decode_utf8().get("")
	return parse(text).to_optional()

fn custom_providers() List[Provider]:
	var out = List[Provider]()
	doc := read_json("models.json")
	if doc.is_none(): return out

	table := doc.get(JsonValue.Null).get("providers").get(JsonValue.Null).as_map().get(
		Map[String, JsonValue]()
	)

	for entry in table.entries():
		body := entry.value
		api := str_or(body, "api", "openai-completions")
		var names = List[String]()
		for model in body.get("models").get(JsonValue.Null).as_list().get([]):
			names.append(str_or(model, "id", ""))
		out.append(
			Provider(
				name: entry.key.clone(),
				api: if api.starts_with(
					"anthropic"
				): "anthropic" else: "openai",
				base_url: str_or(body, "baseUrl", "").trim_end_chars(
					"/"
				),
				key_env: [],
				default_model: names.get(0, ""),
				models: names,
				key: str_or(body, "apiKey", ""),
				keyless: false
			)
		)

	return out

// All providers; a custom one replaces a built-in of the same name.
export fn providers() List[Provider]:
	custom := custom_providers()
	var out = builtin_providers().filter(fn p: not custom.any(fn c: c.name == p.name))
	out.extend(custom)
	return out

export fn find(name: String) Provider?:
	return providers().find(fn p: p.name == name)

// The stored key for `provider`, from auth.json.
fn stored_key(provider: String) String:
	doc := read_json("auth.json")
	if doc.is_none(): return ""

	entry := doc.get(JsonValue.Null).get(provider)
	if entry.is_none(): return ""

	return str_or(entry.get(JsonValue.Null), "key", "")

// Key lookup order: explicit flag, environment, auth.json, models.json.
export fn api_key(provider: Provider, flag: String) String:
	if not flag.is_empty(): return flag.clone()

	env := environment().get(Map[String, String]())
	for name in provider.key_env:
		if value := env.get(name):
			if not value.is_empty(): return value.clone()

	saved := stored_key(provider.name)
	if not saved.is_empty(): return saved
	if provider.keyless: return "none"

	return provider.key.clone()

// Saves a key for `provider` in auth.json, keeping other entries.
export fn save_key(provider: String, key: String) Unit!:
	try create_directory(config_dir(), recursive: true)

	var table = Map[String, JsonValue]()
	existing := read_json("auth.json")
	if doc := existing:
		table = doc.as_map().get(Map[String, JsonValue]())

	var entry = Map[String, JsonValue]()
	entry.add("type", str("api_key"))
	entry.add("key", str(key))
	table.add(provider.clone(), obj(entry))

	text := try render(obj(table))
	return write_file(join([config_dir(), "auth.json"]), text, replace: true).wait()

// "provider/model" or a bare model id of the given provider.
export fn split_model(spec: String, fallback: String) List[String]:
	if spec.is_empty(): return [fallback.clone(), ""]

	parts := spec.split("/", 2)
	if parts.length() == 2 and find(parts[0]).is_some(): return [
		parts[0].clone(), parts[1].clone()
	]

	return [fallback.clone(), spec.clone()]

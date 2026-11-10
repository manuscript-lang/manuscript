// LLM providers: Anthropic Messages and OpenAI-compatible chat completions, both streamed over SSE.
import (
	Ui from "./ui.ms",
	Signal from "@std/concurrency/promise.ms",
	JsonValue, parse from "@std/data/json.ms",
	Bytes from "@std/bytes.ms",
	http_client from "@std/net/net.ms",
	HttpMethod, HttpHeaders, headers from "@std/net/http.ms",
	sse_events, SseEvent from "@std/net/sse.ms",
	read_all from "@std/io/streams.ms",
	seconds from "@std/time.ms",
	str, num, obj, arr, flag, str_or, int_or, render from "./jsonx.ms",
)

export type ProviderConfig:
	// "anthropic" or "openai".
	api: String
	base_url: String
	api_key: String
	model: String
	max_tokens: Int = 8192
	// Extended thinking budget in tokens; 0 turns it off.
	thinking: Int = 0

export type ToolCall:
	id: String
	name: String
	input: JsonValue

// One assistant turn after streaming completes.
export type Turn:
	// Anthropic-format content blocks, ready to store in the history.
	content: JsonValue
	text: String
	tool_calls: List[ToolCall]
	stop_reason: String
	input_tokens: Int
	output_tokens: Int

// One content block under construction.
type Block:
	kind: String
	id: String
	name: String
	text: String
	json: String
	signature: String

// Streaming accumulator shared by both wire formats.
type Acc:
	blocks: List[Block]
	stop_reason: String
	input_tokens: Int
	output_tokens: Int
	// Thinking text received since the caller last took it.
	pending_thinking: String

impl Acc:
	var fn ensure(index: Int, _kind: String) Unit:
		while self.blocks.length() <= index:
			self.blocks.append(
				Block(
					kind: "text", id: "", name: "", text: "", json: "", signature: ""
				)
			)

	// Folds one Anthropic event in; returns text to show, or "".
	var fn anthropic(kind: String, data: JsonValue) String:
		if kind == "message_start":
			if message := data.get("message"):
				if usage := message.get("usage"):
					self.input_tokens = int_or(usage, "input_tokens", 0)
			return ""

		if kind == "content_block_start":
			index := int_or(data, "index", 0)

			if block := data.get("content_block"):
				self.ensure(index, str_or(block, "type", "text"))
				self.blocks[index].kind = str_or(block, "type", "text")
				self.blocks[index].id = str_or(block, "id", "")
				self.blocks[index].name = str_or(block, "name", "")

			return ""

		if kind == "content_block_delta":
			index := int_or(data, "index", 0)
			self.ensure(index, "text")

			if delta := data.get("delta"):
				dkind := str_or(delta, "type", "")

				if dkind == "text_delta":
					piece := str_or(delta, "text", "")
					self.blocks[index].text = "{self.blocks[index].text}{piece}"
					return piece

				if dkind == "thinking_delta":
					piece := str_or(delta, "thinking", "")
					self.blocks[index].text = "{self.blocks[index].text}{piece}"
					self.pending_thinking = "{self.pending_thinking}{piece}"

				if dkind == "signature_delta":
					self.blocks[index].signature = "{self.blocks[index].signature}{str_or(delta, "signature", "")}"
				if dkind == "input_json_delta":
					self.blocks[index].json = "{self.blocks[index].json}{str_or(delta, "partial_json", "")}"

			return ""

		if kind == "message_delta":
			if delta := data.get("delta"):
				stop := str_or(delta, "stop_reason", "")
				if not stop.is_empty(): self.stop_reason = stop

			if usage := data.get("usage"):
				self.output_tokens = int_or(usage, "output_tokens", self.output_tokens)

		return ""

	// Folds one OpenAI chunk in; returns text to show, or "".
	var fn openai(data: JsonValue) String:
		var shown = ""

		if usage := data.get("usage"):
			self.input_tokens = int_or(usage, "prompt_tokens", self.input_tokens)
			self.output_tokens = int_or(usage, "completion_tokens", self.output_tokens)

		choices := data.get("choices")
		if choices.is_none(): return ""

		first := choices.get(JsonValue.Null).at(0)
		if first.is_none(): return ""

		choice := first.get(JsonValue.Null)
		if reason := choice.get("finish_reason"):
			if text := reason.as_string(): self.stop_reason = if text == "tool_calls": "tool_use" else: if text == "length": "max_tokens" else: "end_turn"

		delta := choice.get("delta")
		if delta.is_none(): return ""

		d := delta.get(JsonValue.Null)

		if content := d.get("content"):
			if piece := content.as_string():
				self.ensure(0, "text")
				self.blocks[0].text = "{self.blocks[0].text}{piece}"
				shown = piece

		if calls := d.get("tool_calls"):
			if list := calls.as_list():
				for call in list:
					slot := int_or(call, "index", 0) + 1
					self.ensure(slot, "tool_use")
					self.blocks[slot].kind = "tool_use"
					if id := call.get("id"):
						if text := id.as_string(): self.blocks[slot].id = text

					if function := call.get("function"):
						name := str_or(function, "name", "")
						if not name.is_empty(): self.blocks[slot].name = name

						args := str_or(function, "arguments", "")
						self.blocks[slot].json = "{self.blocks[slot].json}{args}"

		return shown

fn finish(acc: Acc) Turn!:
	var content = List[JsonValue]()
	var calls = List[ToolCall]()
	var text = ""

	for block in acc.blocks:
		if block.kind == "text":
			if block.text.is_empty(): continue

			var b = Map[String, JsonValue]()
			b.add("type", str("text"))
			b.add("text", str(block.text))
			content.append(obj(b))
			text = "{text}{block.text}"

		if block.kind == "thinking":
			var b = Map[String, JsonValue]()
			b.add("type", str("thinking"))
			b.add("thinking", str(block.text))
			b.add("signature", str(block.signature))
			content.append(obj(b))

		if block.kind == "tool_use":
			raw := if block.json.trim().is_empty(): "\{\}" else: block.json.clone()
			input := try parse(raw)
			var b = Map[String, JsonValue]()
			b.add("type", str("tool_use"))
			b.add("id", str(block.id))
			b.add("name", str(block.name))
			b.add("input", input.clone())
			content.append(obj(b))
			calls.append(
				ToolCall(
					id: block.id.clone(), name: block.name.clone(), input: input
				)
			)

	stop := if acc.stop_reason.is_empty(): "end_turn" else: acc.stop_reason.clone()
	return ok(
		Turn(
			content: arr(content), text: text, tool_calls: calls, stop_reason: stop,
			input_tokens: acc.input_tokens, output_tokens: acc.output_tokens
		)
	)

fn anthropic_request(
	cfg: ProviderConfig,
	system: String,
	history: List[JsonValue],
	tools: List[JsonValue]
) String!:
	var body = Map[String, JsonValue]()
	body.add("model", str(cfg.model))
	body.add("max_tokens", num(cfg.max_tokens + cfg.thinking))

	if cfg.thinking > 0:
		var think = Map[String, JsonValue]()
		think.add("type", str("enabled"))
		think.add("budget_tokens", num(cfg.thinking))
		body.add("thinking", obj(think))

	body.add("stream", flag(true))
	body.add("system", str(system))
	body.add("messages", arr(history.clone()))
	if not tools.is_empty(): body.add("tools", arr(tools.clone()))
	return render(obj(body))

// Converts the stored Anthropic-format history into OpenAI chat messages.
fn openai_messages(system: String, history: List[JsonValue]) List[JsonValue]:
	var out = List[JsonValue]()
	var sys = Map[String, JsonValue]()
	sys.add("role", str("system"))
	sys.add("content", str(system))
	out.append(obj(sys))

	for message in history:
		role := str_or(message, "role", "user")
		blocks := message.get("content").get(JsonValue.Null).as_list().get([])
		var text = ""
		var calls = List[JsonValue]()
		var images = List[JsonValue]()

		for block in blocks:
			kind := str_or(block, "type", "")
			if kind == "text": text = "{text}{str_or(block, "text", "")}"

			if kind == "image":
				source := block.get("source").get(JsonValue.Null)
				url := "data:{str_or(source, "media_type", "image/png")};base64,{str_or(source, "data", "")}"
				var link = Map[String, JsonValue]()
				link.add("url", str(url))

				var part = Map[String, JsonValue]()
				part.add("type", str("image_url"))
				part.add("image_url", obj(link))
				images.append(obj(part))

			if kind == "tool_use":
				var fn_map = Map[String, JsonValue]()
				fn_map.add("name", str(str_or(block, "name", "")))
				fn_map.add(
					"arguments",
					str(
						render(
							block.get("input").get(
								JsonValue.Null
							)
						).get("\{\}")
					)
				)

				var call = Map[String, JsonValue]()
				call.add("id", str(str_or(block, "id", "")))
				call.add("type", str("function"))
				call.add("function", obj(fn_map))
				calls.append(obj(call))

			if kind == "tool_result":
				var m = Map[String, JsonValue]()
				m.add("role", str("tool"))
				m.add("tool_call_id", str(str_or(block, "tool_use_id", "")))
				m.add("content", str(str_or(block, "content", "")))
				out.append(obj(m))

		if role == "assistant" or not text.is_empty() or not images.is_empty():
			var m = Map[String, JsonValue]()
			m.add("role", str(role))

			if images.is_empty():
				m.add("content", str(text))
			else:
				var lead = Map[String, JsonValue]()
				lead.add("type", str("text"))
				lead.add("text", str(text))

				var parts = [obj(lead)]
				parts.extend(images)
				m.add("content", arr(parts))

			if not calls.is_empty(): m.add("tool_calls", arr(calls))
			out.append(obj(m))

	return out

fn openai_request(
	cfg: ProviderConfig,
	system: String,
	history: List[JsonValue],
	tools: List[JsonValue]
) String!:
	var body = Map[String, JsonValue]()
	body.add("model", str(cfg.model))
	body.add("stream", flag(true))
	if cfg.thinking > 0: body.add(
		"reasoning_effort",
		str(
			if cfg.thinking >= 16000: "high" else: if cfg.thinking >= 4000: "medium" else: "low"
		)
	)
	body.add("messages", arr(openai_messages(system, history)))

	if not tools.is_empty():
		var wrapped = List[JsonValue]()

		for t in tools:
			var function = Map[String, JsonValue]()
			function.add("name", str(str_or(t, "name", "")))
			function.add("description", str(str_or(t, "description", "")))
			function.add(
				"parameters", t.get("input_schema").get(JsonValue.Null).clone()
			)

			var w = Map[String, JsonValue]()
			w.add("type", str("function"))
			w.add("function", obj(function))
			wrapped.append(obj(w))

		body.add("tools", arr(wrapped))

	return render(obj(body))

// Streams one assistant turn; `on_text` receives each text delta as it arrives.
export fn stream_turn(
	cfg: ProviderConfig,
	system: String,
	history: List[JsonValue],
	tools: List[JsonValue],
	var ui: Ui,
	stop: Signal
) Turn!:
	is_anthropic := cfg.api == "anthropic"
	body := try (
		if is_anthropic: anthropic_request(
			cfg, system, history, tools
		) else: openai_request(cfg, system, history, tools)
	)
	var head = headers()
	try head.append("content-type", "application/json")

	if is_anthropic:
		try head.append("x-api-key", cfg.api_key)
		try head.append("anthropic-version", "2023-06-01")
	else:
		try head.append("authorization", "Bearer {cfg.api_key}")

	url := if is_anthropic: "{cfg.base_url}/v1/messages" else: "{cfg.base_url}/chat/completions"
	client := try http_client()
	response := try client.request(HttpMethod.Post, url, head, body, none, none)
	{metadata: meta, body: payload} := response

	if meta.status >= 400:
		raw := try read_all(payload, 65536)
		detail := raw.decode_utf8().get("")
		return error(Error("API error {meta.status}: {detail}"))

	var acc = Acc(
		blocks: List[Block](), stop_reason: "", input_tokens: 0, output_tokens: 0,
		pending_thinking: ""
	)
	var events = sse_events(payload)

	for ev in events:
		if stop.cancelled(): return error(Error("aborted", kind: "ECANCELED"))
		if ev.data == "[DONE]": break

		data := try parse(ev.data)

		if not is_anthropic:
			shown := acc.openai(data)
			if not shown.is_empty(): ui.text(shown)
			continue

		if ev.event == "error": return error(Error("API stream error: {ev.data}"))

		shown := acc.anthropic(ev.event, data)
		if not shown.is_empty(): ui.text(shown)

		if not acc.pending_thinking.is_empty():
			ui.thinking(acc.pending_thinking)
			acc.pending_thinking = ""

	return finish(acc)

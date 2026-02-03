// Anthropic Claude LLM Adapter
import Anthropic from "@anthropic-ai/sdk";
import type { 
  LLM, 
  Message, 
  LLMConfig, 
  LLMResponse, 
  LLMStreamChunk, 
  ToolDefinition, 
  ToolCall 
} from "../types";

export interface ClaudeConfig {
  model?: string;
  apiKey?: string;
  maxTokens?: number;
}

export class Claude implements LLM {
  private client: Anthropic;
  private defaultModel: string;
  private defaultMaxTokens: number;
  
  constructor(config: ClaudeConfig = {}) {
    this.client = new Anthropic({
      apiKey: config.apiKey || process.env.ANTHROPIC_API_KEY,
    });
    this.defaultModel = config.model || "claude-sonnet-4-20250514";
    this.defaultMaxTokens = config.maxTokens || 4096;
  }
  
  async complete(messages: Message[], config?: Partial<LLMConfig>): Promise<LLMResponse> {
    const systemPrompt = config?.systemPrompt || 
      messages.find(m => m.role === "system")?.content;
    
    const anthropicMessages = messages
      .filter(m => m.role !== "system")
      .map(m => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));
    
    const response = await this.client.messages.create({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      system: systemPrompt,
      messages: anthropicMessages,
      temperature: config?.temperature,
    });
    
    const textContent = response.content.find(c => c.type === "text");
    
    return {
      content: textContent?.type === "text" ? textContent.text : "",
      usage: {
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      },
    };
  }
  
  async *stream(messages: Message[], config?: Partial<LLMConfig>): AsyncIterable<LLMStreamChunk> {
    const systemPrompt = config?.systemPrompt || 
      messages.find(m => m.role === "system")?.content;
    
    const anthropicMessages = messages
      .filter(m => m.role !== "system")
      .map(m => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));
    
    const stream = this.client.messages.stream({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      system: systemPrompt,
      messages: anthropicMessages,
      temperature: config?.temperature,
    });
    
    for await (const event of stream) {
      if (event.type === "content_block_delta") {
        const delta = event.delta;
        if ("text" in delta) {
          yield { type: "text", text: delta.text };
        }
      }
    }
    
    yield { type: "done" };
  }
  
  async completeWithTools(
    messages: Message[],
    tools: ToolDefinition[],
    config?: Partial<LLMConfig>
  ): Promise<LLMResponse> {
    const systemPrompt = config?.systemPrompt || 
      messages.find(m => m.role === "system")?.content;
    
    const anthropicMessages = messages
      .filter(m => m.role !== "system")
      .map(m => {
        if (m.role === "tool") {
          return {
            role: "user" as const,
            content: [
              {
                type: "tool_result" as const,
                tool_use_id: m.toolCallId!,
                content: m.content,
              },
            ],
          };
        }
        return {
          role: m.role as "user" | "assistant",
          content: m.content,
        };
      });
    
    const anthropicTools = tools.map(t => ({
      name: t.name,
      description: t.description,
      input_schema: t.parameters as Anthropic.Tool["input_schema"],
    }));
    
    const response = await this.client.messages.create({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      system: systemPrompt,
      messages: anthropicMessages,
      tools: anthropicTools,
      temperature: config?.temperature,
    });
    
    const textContent = response.content.find(c => c.type === "text");
    const toolUses = response.content.filter(c => c.type === "tool_use");
    
    const toolCalls: ToolCall[] = toolUses.map(t => {
      if (t.type === "tool_use") {
        return {
          id: t.id,
          name: t.name,
          args: t.input as Record<string, any>,
        };
      }
      throw new Error("Unexpected content type");
    });
    
    return {
      content: textContent?.type === "text" ? textContent.text : "",
      toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
      usage: {
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      },
    };
  }
  
  async ask(prompt: string, config?: Partial<LLMConfig>): Promise<string> {
    const response = await this.complete(
      [{ role: "user", content: prompt }],
      config
    );
    return response.content;
  }
  
  async close(): Promise<void> {
    // Anthropic client doesn't need explicit cleanup
  }
}

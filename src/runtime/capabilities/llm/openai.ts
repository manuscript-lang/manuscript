// OpenAI LLM Adapter
import OpenAI from "openai";
import type { 
  LLM, 
  Message, 
  LLMConfig, 
  LLMResponse, 
  LLMStreamChunk, 
  ToolDefinition, 
  ToolCall 
} from "../types";

export interface OpenAIConfig {
  model?: string;
  apiKey?: string;
  maxTokens?: number;
  baseURL?: string;
}

export class GPT implements LLM {
  private client: OpenAI;
  private defaultModel: string;
  private defaultMaxTokens: number;
  
  constructor(config: OpenAIConfig = {}) {
    this.client = new OpenAI({
      apiKey: config.apiKey || process.env.OPENAI_API_KEY,
      baseURL: config.baseURL,
    });
    this.defaultModel = config.model || "gpt-4o";
    this.defaultMaxTokens = config.maxTokens || 4096;
  }
  
  async complete(messages: Message[], config?: Partial<LLMConfig>): Promise<LLMResponse> {
    const openaiMessages: OpenAI.ChatCompletionMessageParam[] = messages.map(m => {
      if (m.role === "system") {
        return { role: "system" as const, content: m.content };
      }
      if (m.role === "assistant") {
        return { role: "assistant" as const, content: m.content };
      }
      return { role: "user" as const, content: m.content };
    });
    
    if (config?.systemPrompt) {
      openaiMessages.unshift({ role: "system", content: config.systemPrompt });
    }
    
    const response = await this.client.chat.completions.create({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      messages: openaiMessages,
      temperature: config?.temperature,
    });
    
    const choice = response.choices[0];
    
    return {
      content: choice?.message?.content || "",
      usage: response.usage ? {
        inputTokens: response.usage.prompt_tokens,
        outputTokens: response.usage.completion_tokens,
      } : undefined,
    };
  }
  
  async *stream(messages: Message[], config?: Partial<LLMConfig>): AsyncIterable<LLMStreamChunk> {
    const openaiMessages: OpenAI.ChatCompletionMessageParam[] = messages.map(m => {
      if (m.role === "system") {
        return { role: "system" as const, content: m.content };
      }
      if (m.role === "assistant") {
        return { role: "assistant" as const, content: m.content };
      }
      return { role: "user" as const, content: m.content };
    });
    
    if (config?.systemPrompt) {
      openaiMessages.unshift({ role: "system", content: config.systemPrompt });
    }
    
    const stream = await this.client.chat.completions.create({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      messages: openaiMessages,
      temperature: config?.temperature,
      stream: true,
    });
    
    for await (const chunk of stream) {
      const delta = chunk.choices[0]?.delta;
      if (delta?.content) {
        yield { type: "text", text: delta.content };
      }
    }
    
    yield { type: "done" };
  }
  
  async completeWithTools(
    messages: Message[],
    tools: ToolDefinition[],
    config?: Partial<LLMConfig>
  ): Promise<LLMResponse> {
    const openaiMessages: OpenAI.ChatCompletionMessageParam[] = messages.map(m => {
      if (m.role === "system") {
        return { role: "system" as const, content: m.content };
      }
      if (m.role === "assistant") {
        return { role: "assistant" as const, content: m.content };
      }
      if (m.role === "tool") {
        return { 
          role: "tool" as const, 
          content: m.content,
          tool_call_id: m.toolCallId!,
        };
      }
      return { role: "user" as const, content: m.content };
    });
    
    if (config?.systemPrompt) {
      openaiMessages.unshift({ role: "system", content: config.systemPrompt });
    }
    
    const openaiTools: OpenAI.ChatCompletionTool[] = tools.map(t => ({
      type: "function" as const,
      function: {
        name: t.name,
        description: t.description,
        parameters: t.parameters,
      },
    }));
    
    const response = await this.client.chat.completions.create({
      model: config?.model || this.defaultModel,
      max_tokens: config?.maxTokens || this.defaultMaxTokens,
      messages: openaiMessages,
      tools: openaiTools,
      temperature: config?.temperature,
    });
    
    const choice = response.choices[0];
    const toolCalls: ToolCall[] = (choice?.message?.tool_calls || []).map(tc => ({
      id: tc.id,
      name: tc.function.name,
      args: JSON.parse(tc.function.arguments),
    }));
    
    return {
      content: choice?.message?.content || "",
      toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
      usage: response.usage ? {
        inputTokens: response.usage.prompt_tokens,
        outputTokens: response.usage.completion_tokens,
      } : undefined,
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
    // OpenAI client doesn't need explicit cleanup
  }
}

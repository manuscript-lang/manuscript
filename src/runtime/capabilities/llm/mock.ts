// Mock LLM for Testing
import type { 
  LLM, 
  Message, 
  LLMConfig, 
  LLMResponse, 
  LLMStreamChunk, 
  ToolDefinition, 
  ToolCall 
} from "../types";

export interface MockResponse {
  match: string | RegExp;
  reply: string;
  toolCalls?: ToolCall[];
}

export interface MockLLMConfig {
  responses?: MockResponse[];
  defaultReply?: string;
  delay?: number;
}

export class MockLLM implements LLM {
  private responses: MockResponse[];
  private defaultReply: string;
  private delay: number;
  private callHistory: { messages: Message[]; config?: Partial<LLMConfig> }[] = [];
  
  constructor(config: MockLLMConfig = {}) {
    this.responses = config.responses || [];
    this.defaultReply = config.defaultReply || "Mock response";
    this.delay = config.delay || 0;
  }
  
  // Get call history for assertions
  getCalls(): { messages: Message[]; config?: Partial<LLMConfig> }[] {
    return this.callHistory;
  }
  
  // Clear call history
  clearCalls(): void {
    this.callHistory = [];
  }
  
  // Add a mock response
  addResponse(match: string | RegExp, reply: string, toolCalls?: ToolCall[]): void {
    this.responses.push({ match, reply, toolCalls });
  }
  
  private findResponse(messages: Message[]): MockResponse | undefined {
    const lastUserMessage = [...messages].reverse().find(m => m.role === "user");
    if (!lastUserMessage) return undefined;
    
    for (const response of this.responses) {
      if (typeof response.match === "string") {
        if (lastUserMessage.content.includes(response.match)) {
          return response;
        }
      } else {
        if (response.match.test(lastUserMessage.content)) {
          return response;
        }
      }
    }
    return undefined;
  }
  
  async complete(messages: Message[], config?: Partial<LLMConfig>): Promise<LLMResponse> {
    this.callHistory.push({ messages, config });
    
    if (this.delay > 0) {
      await new Promise(resolve => setTimeout(resolve, this.delay));
    }
    
    const response = this.findResponse(messages);
    
    return {
      content: response?.reply || this.defaultReply,
      toolCalls: response?.toolCalls,
      usage: {
        inputTokens: messages.reduce((acc, m) => acc + m.content.length, 0),
        outputTokens: (response?.reply || this.defaultReply).length,
      },
    };
  }
  
  async *stream(messages: Message[], config?: Partial<LLMConfig>): AsyncIterable<LLMStreamChunk> {
    this.callHistory.push({ messages, config });
    
    const response = this.findResponse(messages);
    const content = response?.reply || this.defaultReply;
    
    // Simulate streaming by yielding words
    const words = content.split(" ");
    for (let i = 0; i < words.length; i++) {
      if (this.delay > 0) {
        await new Promise(resolve => setTimeout(resolve, this.delay / words.length));
      }
      yield { type: "text", text: words[i] + (i < words.length - 1 ? " " : "") };
    }
    
    if (response?.toolCalls) {
      for (const toolCall of response.toolCalls) {
        yield { type: "tool_call", toolCall };
      }
    }
    
    yield { type: "done" };
  }
  
  async completeWithTools(
    messages: Message[],
    tools: ToolDefinition[],
    config?: Partial<LLMConfig>
  ): Promise<LLMResponse> {
    return this.complete(messages, config);
  }
  
  async ask(prompt: string, config?: Partial<LLMConfig>): Promise<string> {
    const response = await this.complete(
      [{ role: "user", content: prompt }],
      config
    );
    return response.content;
  }
  
  async close(): Promise<void> {
    // No cleanup needed
  }
}

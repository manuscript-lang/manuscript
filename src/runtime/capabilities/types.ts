// Capability Type Definitions

// ============================================
// LLM Types
// ============================================

export interface Message {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  name?: string;
  toolCallId?: string;
}

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: Record<string, any>;
}

export interface ToolCall {
  id: string;
  name: string;
  args: Record<string, any>;
}

export interface LLMResponse {
  content: string;
  toolCalls?: ToolCall[];
  usage?: { inputTokens: number; outputTokens: number };
}

export interface LLMStreamChunk {
  type: "text" | "thinking" | "tool_call" | "done";
  text?: string;
  toolCall?: ToolCall;
}

export interface LLMConfig {
  model: string;
  maxTokens?: number;
  temperature?: number;
  systemPrompt?: string;
}

export interface LLM {
  complete(messages: Message[], config?: Partial<LLMConfig>): Promise<LLMResponse>;
  stream(messages: Message[], config?: Partial<LLMConfig>): AsyncIterable<LLMStreamChunk>;
  completeWithTools(messages: Message[], tools: ToolDefinition[], config?: Partial<LLMConfig>): Promise<LLMResponse>;
  ask(prompt: string, config?: Partial<LLMConfig>): Promise<string>;
  close(): Promise<void>;
}

// ============================================
// Filesystem Types
// ============================================

export interface FileInfo {
  path: string;
  name: string;
  isDirectory: boolean;
  size: number;
  modified: Date;
}

export interface Filesystem {
  read(path: string): Promise<string>;
  readBytes(path: string): Promise<Uint8Array>;
  exists(path: string): Promise<boolean>;
  stat(path: string): Promise<FileInfo>;
  list(path: string): Promise<FileInfo[]>;
  glob(pattern: string): Promise<string[]>;
  write(path: string, content: string): Promise<void>;
  writeBytes(path: string, content: Uint8Array): Promise<void>;
  append(path: string, content: string): Promise<void>;
  mkdir(path: string): Promise<void>;
  remove(path: string): Promise<void>;
  copy(src: string, dest: string): Promise<void>;
  move(src: string, dest: string): Promise<void>;
  join(...parts: string[]): string;
  dirname(path: string): string;
  basename(path: string): string;
  resolve(path: string): string;
}

// ============================================
// Shell Types
// ============================================

export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface ExecOptions {
  cwd?: string;
  env?: Record<string, string>;
  timeout?: number;
  stdin?: string;
}

export interface Shell {
  exec(command: string, options?: ExecOptions): Promise<ExecResult>;
  spawn(command: string, options?: ExecOptions): AsyncIterable<string>;
  which(command: string): Promise<string | null>;
  cwd(): string;
  env(name: string): string | undefined;
}

// ============================================
// HTTP Types
// ============================================

export interface HTTPResponse {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  body: string;
}

export interface HTTPOptions {
  headers?: Record<string, string>;
  body?: string | Record<string, any>;
  timeout?: number;
}

export interface HTTP {
  get(url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  post(url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  put(url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  patch(url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  delete(url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  request(method: string, url: string, options?: HTTPOptions): Promise<HTTPResponse>;
  getJSON<T = any>(url: string, options?: HTTPOptions): Promise<T>;
  postJSON<T = any>(url: string, data: any, options?: HTTPOptions): Promise<T>;
}

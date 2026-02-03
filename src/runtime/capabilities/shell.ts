// Shell Capability Adapters
import { spawn as bunSpawn, type Subprocess } from "bun";
import type { Shell, ExecResult, ExecOptions } from "./types";

// ============================================
// Local Shell
// ============================================

export interface LocalShellConfig {
  shell?: string;  // Shell to use (default: /bin/sh)
  cwd?: string;    // Working directory
}

export class LocalShell implements Shell {
  private shellPath: string;
  private workingDir: string;
  
  constructor(config: LocalShellConfig = {}) {
    this.shellPath = config.shell || "/bin/sh";
    this.workingDir = config.cwd || process.cwd();
  }
  
  async exec(command: string, options?: ExecOptions): Promise<ExecResult> {
    const proc = bunSpawn({
      cmd: [this.shellPath, "-c", command],
      cwd: options?.cwd || this.workingDir,
      env: { ...process.env, ...options?.env },
      stdin: options?.stdin ? new Response(options.stdin) : undefined,
      stdout: "pipe",
      stderr: "pipe",
    });
    
    // Handle timeout
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    if (options?.timeout) {
      timeoutId = setTimeout(() => {
        proc.kill();
      }, options.timeout);
    }
    
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    
    const exitCode = await proc.exited;
    
    if (timeoutId) {
      clearTimeout(timeoutId);
    }
    
    return { stdout, stderr, exitCode };
  }
  
  async *spawn(command: string, options?: ExecOptions): AsyncIterable<string> {
    const proc = bunSpawn({
      cmd: [this.shellPath, "-c", command],
      cwd: options?.cwd || this.workingDir,
      env: { ...process.env, ...options?.env },
      stdin: options?.stdin ? new Response(options.stdin) : undefined,
      stdout: "pipe",
      stderr: "pipe",
    });
    
    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();
    
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        yield decoder.decode(value, { stream: true });
      }
    } finally {
      reader.releaseLock();
    }
  }
  
  async which(command: string): Promise<string | null> {
    try {
      const result = await this.exec(`which ${command}`);
      if (result.exitCode === 0) {
        return result.stdout.trim();
      }
      return null;
    } catch {
      return null;
    }
  }
  
  cwd(): string {
    return this.workingDir;
  }
  
  env(name: string): string | undefined {
    return process.env[name];
  }
}

// ============================================
// Mock Shell for Testing
// ============================================

export interface MockCommand {
  match: string | RegExp;
  stdout?: string;
  stderr?: string;
  exitCode?: number;
}

export interface MockShellConfig {
  commands?: MockCommand[];
  cwd?: string;
  env?: Record<string, string>;
}

export class MockShell implements Shell {
  private commands: MockCommand[];
  private workingDir: string;
  private environment: Record<string, string>;
  private execHistory: { command: string; options?: ExecOptions }[] = [];
  
  constructor(config: MockShellConfig = {}) {
    this.commands = config.commands || [];
    this.workingDir = config.cwd || "/mock/cwd";
    this.environment = config.env || {};
  }
  
  // Test helpers
  getExecHistory(): { command: string; options?: ExecOptions }[] {
    return this.execHistory;
  }
  
  clearHistory(): void {
    this.execHistory = [];
  }
  
  addCommand(match: string | RegExp, result: Partial<ExecResult>): void {
    this.commands.push({
      match,
      stdout: result.stdout || "",
      stderr: result.stderr || "",
      exitCode: result.exitCode ?? 0,
    });
  }
  
  private findCommand(command: string): MockCommand | undefined {
    for (const mock of this.commands) {
      if (typeof mock.match === "string") {
        if (command.includes(mock.match)) {
          return mock;
        }
      } else {
        if (mock.match.test(command)) {
          return mock;
        }
      }
    }
    return undefined;
  }
  
  async exec(command: string, options?: ExecOptions): Promise<ExecResult> {
    this.execHistory.push({ command, options });
    
    const mock = this.findCommand(command);
    if (mock) {
      return {
        stdout: mock.stdout || "",
        stderr: mock.stderr || "",
        exitCode: mock.exitCode ?? 0,
      };
    }
    
    // Default: command not found
    return {
      stdout: "",
      stderr: `mock: command not found: ${command}`,
      exitCode: 127,
    };
  }
  
  async *spawn(command: string, options?: ExecOptions): AsyncIterable<string> {
    this.execHistory.push({ command, options });
    
    const mock = this.findCommand(command);
    if (mock && mock.stdout) {
      // Simulate streaming by yielding line by line
      const lines = mock.stdout.split("\n");
      for (const line of lines) {
        yield line + "\n";
      }
    }
  }
  
  async which(command: string): Promise<string | null> {
    // Mock always returns a path for common commands
    const common = ["ls", "cat", "grep", "node", "bun", "npm"];
    if (common.includes(command)) {
      return `/usr/bin/${command}`;
    }
    return null;
  }
  
  cwd(): string {
    return this.workingDir;
  }
  
  env(name: string): string | undefined {
    return this.environment[name];
  }
}

// Agent Base Class with Resource Limits

export interface AgentLimits {
  maxTurns?: number;      // Maximum conversation turns
  timeout?: number;       // Timeout in ms for entire run
  turnTimeout?: number;   // Timeout in ms per turn
  rateLimit?: number;     // Max calls per minute
}

export class Agent {
  protected capabilities: Map<string, any> = new Map();
  protected tools: Map<string, Function> = new Map();
  protected limits: AgentLimits = {};
  protected turnCount = 0;
  protected callTimes: number[] = [];
  protected startTime = 0;

  constructor(limits?: AgentLimits) {
    if (limits) this.limits = limits;
  }

  async run(...args: any[]): Promise<any> {
    throw new Error("Agent.run() must be implemented");
  }

  // Check resource limits before each turn
  protected checkLimits(): void {
    // Turn limit
    if (this.limits.maxTurns && this.turnCount >= this.limits.maxTurns) {
      throw new Error(`Agent exceeded turn limit of ${this.limits.maxTurns}`);
    }
    
    // Total timeout
    if (this.limits.timeout && this.startTime > 0) {
      const elapsed = Date.now() - this.startTime;
      if (elapsed > this.limits.timeout) {
        throw new Error(`Agent exceeded timeout of ${this.limits.timeout}ms`);
      }
    }
    
    // Rate limit (sliding window)
    if (this.limits.rateLimit) {
      const now = Date.now();
      const oneMinuteAgo = now - 60000;
      this.callTimes = this.callTimes.filter(t => t > oneMinuteAgo);
      if (this.callTimes.length >= this.limits.rateLimit) {
        throw new Error(`Agent exceeded rate limit of ${this.limits.rateLimit} calls/minute`);
      }
      this.callTimes.push(now);
    }
  }

  // Start tracking for a new run
  protected startRun(): void {
    this.turnCount = 0;
    this.startTime = Date.now();
  }

  // Increment turn counter
  protected incrementTurn(): void {
    this.turnCount++;
  }

  protected useTool(name: string, ...args: any[]): Promise<any> {
    const tool = this.tools.get(name);
    if (!tool) throw new Error(`Tool '${name}' not found`);
    return tool.apply(this, args);
  }

  // Wrap an async operation with turn timeout
  protected async withTurnTimeout<T>(operation: () => Promise<T>): Promise<T> {
    if (!this.limits.turnTimeout) return operation();
    
    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error(`Turn exceeded timeout of ${this.limits.turnTimeout}ms`)), 
                 this.limits.turnTimeout);
    });
    
    return Promise.race([operation(), timeoutPromise]);
  }
}

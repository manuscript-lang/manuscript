// Agent Base Class

export class Agent {
  protected capabilities: Map<string, any> = new Map();
  protected tools: Map<string, Function> = new Map();

  constructor() {}

  async run(...args: any[]): Promise<any> {
    throw new Error("Agent.run() must be implemented");
  }

  protected useTool(name: string, ...args: any[]): Promise<any> {
    const tool = this.tools.get(name);
    if (!tool) throw new Error(`Tool '${name}' not found`);
    return tool.apply(this, args);
  }
}

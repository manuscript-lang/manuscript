import { describe, test, expect } from "bun:test";
import { Agent } from "../../src/runtime/agent";

describe("Runtime - Agent Base Class", () => {
  test("Agent.run() throws not implemented error", async () => {
    const agent = new Agent();
    await expect(agent.run()).rejects.toThrow("Agent.run() must be implemented");
  });

  test("subclass can override run()", async () => {
    class MyAgent extends Agent {
      override async run(input: string): Promise<string> {
        return `processed: ${input}`;
      }
    }
    
    const agent = new MyAgent();
    const result = await agent.run("test");
    expect(result).toBe("processed: test");
  });

  test("useTool throws when tool not found", async () => {
    class MyAgent extends Agent {
      override async run(): Promise<any> {
        return this.useTool("nonexistent");
      }
    }
    
    const agent = new MyAgent();
    await expect(agent.run()).rejects.toThrow("Tool 'nonexistent' not found");
  });

  test("useTool executes registered tool", async () => {
    class MyAgent extends Agent {
      constructor() {
        super();
        this.tools.set("greet", (name: string) => `Hello, ${name}`);
      }
      
      override async run(name: string): Promise<any> {
        return this.useTool("greet", name);
      }
    }
    
    const agent = new MyAgent();
    const result = await agent.run("World");
    expect(result).toBe("Hello, World");
  });
});

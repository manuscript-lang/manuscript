import { describe, test, expect } from "bun:test";
import { MockLLM } from "../../src/runtime/capabilities/llm/mock";
import { MockFilesystem } from "../../src/runtime/capabilities/filesystem";
import { MockShell } from "../../src/runtime/capabilities/shell";
import { MockHTTP } from "../../src/runtime/capabilities/http";

describe("MockLLM", () => {
  test("returns default reply", async () => {
    const llm = new MockLLM({ defaultReply: "Hello!" });
    const response = await llm.ask("Hi");
    expect(response).toBe("Hello!");
  });

  test("matches responses by string", async () => {
    const llm = new MockLLM({
      responses: [
        { match: "hello", reply: "Hi there!" },
        { match: "bye", reply: "Goodbye!" },
      ],
      defaultReply: "Unknown",
    });

    expect(await llm.ask("hello world")).toBe("Hi there!");
    expect(await llm.ask("bye bye")).toBe("Goodbye!");
    expect(await llm.ask("something else")).toBe("Unknown");
  });

  test("matches responses by regex", async () => {
    const llm = new MockLLM({
      responses: [
        { match: /^greet/i, reply: "Greetings!" },
      ],
    });

    expect(await llm.ask("GREET me")).toBe("Greetings!");
  });

  test("records call history", async () => {
    const llm = new MockLLM();
    await llm.ask("First");
    await llm.ask("Second");

    const calls = llm.getCalls();
    expect(calls.length).toBe(2);
    expect(calls[0]!.messages[0]!.content).toBe("First");
    expect(calls[1]!.messages[0]!.content).toBe("Second");
  });

  test("streams response word by word", async () => {
    const llm = new MockLLM({ defaultReply: "Hello world" });
    const chunks: string[] = [];

    for await (const chunk of llm.stream([{ role: "user", content: "test" }])) {
      if (chunk.type === "text" && chunk.text) {
        chunks.push(chunk.text);
      }
    }

    expect(chunks.join("")).toBe("Hello world");
  });

  test("complete returns usage stats", async () => {
    const llm = new MockLLM({ defaultReply: "Reply" });
    const response = await llm.complete([{ role: "user", content: "Test message" }]);

    expect(response.usage).toBeDefined();
    expect(response.usage!.inputTokens).toBe(12); // "Test message".length
    expect(response.usage!.outputTokens).toBe(5); // "Reply".length
  });
});

describe("MockFilesystem", () => {
  test("reads pre-configured files", async () => {
    const fs = new MockFilesystem({
      files: { "test.txt": "Hello" },
    });

    expect(await fs.read("test.txt")).toBe("Hello");
  });

  test("throws on missing file", async () => {
    const fs = new MockFilesystem();
    await expect(fs.read("missing.txt")).rejects.toThrow("ENOENT");
  });

  test("writes files", async () => {
    const fs = new MockFilesystem();
    await fs.write("new.txt", "Content");
    expect(await fs.read("new.txt")).toBe("Content");
  });

  test("checks existence", async () => {
    const fs = new MockFilesystem({ files: { "exists.txt": "" } });
    expect(await fs.exists("exists.txt")).toBe(true);
    expect(await fs.exists("missing.txt")).toBe(false);
  });

  test("appends to files", async () => {
    const fs = new MockFilesystem({ files: { "log.txt": "Line 1\n" } });
    await fs.append("log.txt", "Line 2\n");
    expect(await fs.read("log.txt")).toBe("Line 1\nLine 2\n");
  });

  test("glob matches files", async () => {
    const fs = new MockFilesystem({
      files: {
        "src/a.ts": "",
        "src/b.ts": "",
        "src/c.js": "",
        "test/d.ts": "",
      },
    });

    const tsFiles = await fs.glob("src/*.ts");
    expect(tsFiles.length).toBe(2);
    expect(tsFiles).toContain("src/a.ts");
    expect(tsFiles).toContain("src/b.ts");
  });

  test("stat returns file info", async () => {
    const fs = new MockFilesystem({ files: { "test.txt": "content" } });
    const info = await fs.stat("test.txt");

    expect(info.name).toBe("test.txt");
    expect(info.isDirectory).toBe(false);
    expect(info.size).toBe(7); // "content".length
  });

  test("path utilities work", () => {
    const fs = new MockFilesystem();
    expect(fs.join("a", "b", "c")).toBe("a/b/c");
    expect(fs.dirname("a/b/c.txt")).toBe("a/b");
    expect(fs.basename("a/b/c.txt")).toBe("c.txt");
  });
});

describe("MockShell", () => {
  test("returns configured command output", async () => {
    const shell = new MockShell({
      commands: [
        { match: "echo", stdout: "Hello\n", exitCode: 0 },
      ],
    });

    const result = await shell.exec("echo Hello");
    expect(result.stdout).toBe("Hello\n");
    expect(result.exitCode).toBe(0);
  });

  test("returns error for unknown commands", async () => {
    const shell = new MockShell();
    const result = await shell.exec("unknown-command");

    expect(result.exitCode).toBe(127);
    expect(result.stderr).toContain("command not found");
  });

  test("matches commands by regex", async () => {
    const shell = new MockShell({
      commands: [
        { match: /^ls/, stdout: "file1\nfile2\n" },
      ],
    });

    const result = await shell.exec("ls -la");
    expect(result.stdout).toBe("file1\nfile2\n");
  });

  test("records execution history", async () => {
    const shell = new MockShell();
    await shell.exec("cmd1");
    await shell.exec("cmd2", { cwd: "/some/path" });

    const history = shell.getExecHistory();
    expect(history.length).toBe(2);
    expect(history[0]!.command).toBe("cmd1");
    expect(history[1]!.command).toBe("cmd2");
    expect(history[1]!.options?.cwd).toBe("/some/path");
  });

  test("which returns paths for common commands", async () => {
    const shell = new MockShell();
    expect(await shell.which("ls")).toBe("/usr/bin/ls");
    expect(await shell.which("node")).toBe("/usr/bin/node");
    expect(await shell.which("unknown")).toBeNull();
  });

  test("cwd and env work", () => {
    const shell = new MockShell({ cwd: "/test", env: { FOO: "bar" } });
    expect(shell.cwd()).toBe("/test");
    expect(shell.env("FOO")).toBe("bar");
  });
});

describe("MockHTTP", () => {
  test("returns configured responses", async () => {
    const http = new MockHTTP({
      responses: [
        { match: "/api/users", response: { status: 200, body: '{"users":[]}' } },
      ],
    });

    const response = await http.get("/api/users");
    expect(response.status).toBe(200);
    expect(response.body).toBe('{"users":[]}');
  });

  test("returns 404 for unknown routes", async () => {
    const http = new MockHTTP();
    const response = await http.get("/unknown");

    expect(response.status).toBe(404);
  });

  test("matches by method", async () => {
    const http = new MockHTTP({
      responses: [
        { match: "/api/users", method: "POST", response: { status: 201, body: '{"id":1}' } },
        { match: "/api/users", method: "GET", response: { status: 200, body: '[]' } },
      ],
    });

    expect((await http.get("/api/users")).status).toBe(200);
    expect((await http.post("/api/users")).status).toBe(201);
  });

  test("records request history", async () => {
    const http = new MockHTTP();
    await http.get("/api/a");
    await http.post("/api/b", { body: { data: 1 } });

    const history = http.getRequestHistory();
    expect(history.length).toBe(2);
    expect(history[0]!.method).toBe("GET");
    expect(history[1]!.method).toBe("POST");
  });

  test("getJSON and postJSON work", async () => {
    const http = new MockHTTP({
      responses: [
        { match: "/api/data", method: "GET", response: { body: '{"value":42}' } },
        { match: "/api/data", method: "POST", response: { body: '{"created":true}' } },
      ],
    });

    const getData = await http.getJSON("/api/data");
    expect(getData.value).toBe(42);

    const postData = await http.postJSON("/api/data", { input: "test" });
    expect(postData.created).toBe(true);
  });
});

# Manuscript Language Requirements

A language for building agents and multi-agent systems, designed to be readable by non-engineers, testable without external dependencies, and safe for production use.

**Target runtime:** Bun

---

## 1. Design Principles

### 1.1 Readability
- Non-engineers (product managers, domain experts) must be able to read and understand agent logic
- Syntax must read like instructions, not code
- Long prompts must feel natural, not escaped or cluttered with syntax
- The language must have minimal, consistent constructs (learn one pattern, apply everywhere)

### 1.2 Explicit Dependencies
- No magic globals or implicit binding
- All external dependencies must be declared at the point of definition
- It must be immediately clear what an agent, tool, or workflow needs to function
- Dependencies flow from outer scope to inner scope, never implicitly

### 1.3 Testability
- The same agent definition must work with real or mock capabilities without modification
- Capabilities are provided at runtime, not hardcoded in definitions
- Mock capabilities must follow the exact same interface as real implementations
- All invocations must be recordable for test assertions

### 1.4 Composability
- The language has few primitive concepts that combine naturally
- Capabilities, tools, agents, and workflows layer cleanly without special cases
- Memory strategies are composable functions
- Prompts are composable templates

### 1.5 Observability
- Every capability invocation can be monitored without modifying agent code
- Lifecycle hooks are available for logging, metrics, and debugging
- Complete audit trail is available for all external interactions
- Observation must never affect agent logic or control flow

### 1.6 Safety
- Capabilities support sandboxing (restricted file paths, command allowlists)
- Agents have configurable turn limits to prevent infinite loops
- All external calls have configurable timeouts
- Resource limits are enforceable (token budgets, API rate limits)

### 1.7 Predictability
- No syntax surprises - LLMs can generate valid code reliably
- One way to express each concept (no synonyms or alternatives)
- Consistent patterns across all constructs
- Clear evaluation order with no hidden side effects

---

## 2. Core Concepts

The language has exactly six core concepts:

| Concept | Purpose |
|---------|---------|
| Capability | Access to external systems (LLM, database, HTTP, filesystem, shell) |
| Tool | Function that uses capabilities, callable by LLM |
| Agent | LLM-powered unit with prompt, tools, and conversation state |
| Workflow | Orchestration of multiple agents |
| Prompt | Reusable text template with interpolation |
| Service | Stateful object without LLM (optional, for data/caching) |

### 2.1 Capabilities

Capabilities grant controlled access to external systems or functionality.

**Types:**

| Type | Description | Examples |
|------|-------------|----------|
| Connection | Stateful link to external system | LLM providers (Anthropic, OpenAI), Databases (Postgres, SQLite) |
| Functional | Ability to perform operations | HTTP client, Filesystem access, Shell execution |

**Requirements:**

- Capabilities must be instantiated with configuration
- Configuration must support environment variable references
- Every capability must have a corresponding mock implementation
- Capabilities can be grouped into named sets (production, development, testing)
- All capability operations must be auditable (input, output, duration, errors)
- Capabilities must support configuration options:
  - Timeouts
  - Retry policies
  - Sandboxing rules (where applicable)
  - Rate limits (where applicable)

**Built-in Capabilities:**

| Capability | Required Operations |
|------------|---------------------|
| LLM | Complete messages; support temperature, max tokens, stop sequences |
| Database | Query (raw SQL), find by ID, insert, update, delete |
| HTTP | GET, POST, PUT, DELETE; support headers, body, timeout |
| Filesystem | Read, write, append, delete, exists, list directory |
| Shell | Execute command; support working directory, timeout, environment |

**Capability Composition:**

- Capabilities must be composable/stackable
- A capability group can extend another group, overriding specific capabilities
- This enables swapping implementations (e.g., Postgres → SQLite, Anthropic → OpenAI)

### 2.2 Tools

Tools are functions that use capabilities and can be invoked by the LLM during agent execution.

**Requirements:**

- Tools must declare their capability dependencies explicitly
- Tools must have a description (used by LLM to understand when to call)
- Tools must have named parameters with descriptions
- Tool execution must be observable (name, arguments, result, duration)
- Tools must return a value (or null)
- Tool failures must be catchable and recoverable

### 2.3 Agents

Agents are LLM-powered units that can converse, use tools, and maintain state.

**Requirements:**

- Agents must declare their capability dependencies explicitly
- Agents must have a system prompt (can use prompt templates)
- Agents can accept parameters at creation (e.g., customerId, task)
- Agents can have an optional set of tools
- Agents can have mutable state that persists across turns
- Agents must have access to their conversation history (messages)
- Agents must support configurable turn limits
- Agents must support configurable memory strategies

**Lifecycle:**

| Phase | Timing | Purpose |
|-------|--------|---------|
| Initialization | Once, at creation | Load context, fetch data, validate parameters, initialize state |
| System prompt evaluation | Once, after init | Populate prompt template with data from initialization |
| Conversation loop | Per user message | Process input, call LLM, execute tools, update state, return response |
| Termination | Once, at end | Save transcript, cleanup resources, final logging |

**Invocation Modes:**

| Mode | Description | History |
|------|-------------|---------|
| One-shot | Single input → single output | Not maintained |
| Conversational | Multiple turns | Maintained automatically |

**Structured Output:**

- Agents must support structured output (not just text)
- LLM responses can be constrained to a schema (for routing, data extraction)
- Tool return values must support structured data (maps, lists)

**Handoff:**

- An agent must be able to transfer conversation to another agent
- Handoff must preserve relevant context (messages, extracted data)
- Handoff target can be determined dynamically (e.g., based on classifier)

### 2.4 Workflows

Workflows orchestrate multiple agents to accomplish complex tasks.

**Requirements:**

- Workflows must declare their capability dependencies
- Workflows are functions that call agents and return results
- Workflows must support all orchestration patterns (see Section 6)
- Workflow execution must be observable
- Workflows must support cancellation (stop mid-execution)
- Workflows must support timeouts (max duration for entire workflow)

**Error Handling:**

- Workflow must define behavior when an agent fails
- Options: fail entire workflow, continue with partial results, retry, fallback
- Parallel execution must handle partial failures (some succeed, some fail)
- Errors must propagate with context (which agent, which step, what input)

**Shared Context:**

- Workflows must support shared context accessible by all agents within
- Shared context can hold: intermediate results, accumulated data, configuration
- Shared context is distinct from individual agent state

### 2.5 Prompts

Prompts are reusable text templates for system prompts and other text generation.

**Requirements:**

- Prompts must support value interpolation
- Prompts must support conditional sections (if/else)
- Prompts must support iteration over lists (for loops)
- Prompts must support filters for value transformation
- Prompts must be composable (a prompt can include another prompt)
- Multi-line prompts must be natural (no escaping required)

**Required Filters:**

| Category | Filters |
|----------|---------|
| Text | uppercase, lowercase, trim, truncate, pad |
| Formatting | number formatting, date formatting, currency |
| Data | JSON encode, URL encode |
| Default | default value if null |

### 2.6 Services (Optional)

Services are stateful objects that do not use LLM, for data management and caching.

**Requirements:**

- Services must declare their capability dependencies
- Services have named methods (not triggered by LLM)
- Services can have mutable state
- Services are useful for: caches, repositories, connection pools, rate limiters

---

## 3. Agent Lifecycle

### 3.1 Creation

When an agent is created with parameters:

1. Capability dependencies are resolved from the current scope
2. Initialization logic runs (data fetching, validation, state setup)
3. System prompt template is evaluated with initialization data
4. Agent is ready to receive messages

### 3.2 Conversation Loop

For each user message:

1. User message is added to history
2. Memory strategy is applied if context approaches token limit
3. LLM is called with: system prompt + conversation history + tool definitions
4. If LLM returns tool calls:
   - Execute each tool
   - Add tool results to history
   - Return to step 3
5. LLM response is added to history
6. Response is returned to caller

### 3.3 Termination

An agent terminates when:

- Caller explicitly ends the conversation
- Turn limit is reached
- LLM invokes a special "done" tool (for task-completion agents)
- An unrecoverable error occurs
- Caller cancels the agent mid-execution
- Timeout is reached

**Cancellation:**

- Agents must support cancellation at any point
- Cancellation must be graceful (not abrupt kill)
- On cancellation: current operation completes, then termination hook runs
- Cancellation must propagate to child tool executions

On termination:

1. Termination hook runs (save transcript, log metrics)
2. Resources are released

### 3.4 Agent State vs Memory

These are distinct concepts:

| Concept | Purpose | Persistence |
|---------|---------|-------------|
| State | Agent's mutable data (counters, collected info, flags) | Entire conversation |
| Memory | Conversation history (messages) | Managed by memory strategy |

- State is explicitly defined and modified by agent logic
- Memory is automatically managed; agents can read but typically don't modify directly

---

## 4. Memory Management

Memory strategies manage conversation history to stay within LLM context limits.

**Requirements:**

- Memory strategies are functions: messages → messages
- Memory strategies can use capabilities (e.g., LLM for summarization)
- Memory strategies are applied automatically when context approaches limits
- Memory strategies can be composed

**Built-in Strategies:**

| Strategy | Behavior |
|----------|----------|
| Sliding window | Keep last N messages, discard older |
| Summarization | Use LLM to summarize older messages, keep recent verbatim |
| Hierarchical | Multiple tiers: recent = full detail, older = condensed, oldest = summarized |

**Configuration:**

- Token limit threshold (when to trigger compaction)
- Number of recent messages to always preserve
- Custom summarization prompts

---

## 5. Dependency Injection

### 5.1 Declaration

- Tools, agents, workflows, and services must declare required capabilities
- Declarations must be explicit and visible at the definition site
- A definition cannot use a capability it hasn't declared

### 5.2 Provision

- Capabilities are provided via a scoping mechanism at runtime
- The scope provides named capabilities to all code within it
- Nested scopes can override outer scope capabilities
- The same definition can run with different capability sets:
  - Production (real LLM, real database)
  - Development (cheaper LLM, local database)
  - Testing (mock LLM, in-memory database)

### 5.3 Resolution

- When an agent/tool/workflow runs, it receives capabilities from the current scope
- Missing required capabilities cause a clear error at runtime
- Capabilities are resolved once at creation, not per-invocation

---

## 6. Workflow Patterns

The language must support these orchestration patterns:

| Pattern | Description |
|---------|-------------|
| Sequential | Execute agents in sequence, output of one becomes input of next |
| Parallel | Execute multiple agents simultaneously, collect all results |
| Parallel map | Execute an agent for each item in a collection, in parallel |
| Conditional | Route to different agents based on a value (match/switch) |
| Iteration | Repeat until condition met or limit reached |

**Requirements:**

- Parallel execution must be explicit (no implicit parallelism)
- Iteration must have mandatory limits (no unbounded loops)
- Results from parallel execution must be collected into a list
- Conditional routing must have a default/fallback case

**Error Handling in Workflows:**

| Scenario | Required Behavior |
|----------|-------------------|
| Agent fails in sequence | Stop workflow, return error with context |
| Agent fails in parallel | Options: fail all, continue and collect partial results |
| All retries exhausted | Fail with clear error, include all attempt details |
| Timeout reached | Cancel running agents, return partial results or error |

**Cancellation in Workflows:**

- Workflows must be cancellable at any point
- Cancellation must propagate to all running agents
- Partial results must be available after cancellation (where applicable)

---

## 7. Expression Language

### 7.1 Data Types

The language must support these data types:

| Type | Description |
|------|-------------|
| Number | Integers and floating point |
| String | Text, with interpolation support |
| Boolean | true, false |
| Null | Absence of value |
| List | Ordered collection |
| Map | Key-value pairs |

### 7.2 Operators

| Category | Required Operators |
|----------|-------------------|
| Arithmetic | add, subtract, multiply, divide, modulo, power |
| Comparison | equal, not equal, less than, greater than, less or equal, greater or equal |
| Logical | and, or, not |
| Null handling | null coalescing, optional chaining |
| Collection | index access, property access |

### 7.3 Control Flow

- Variable binding (immutable by default)
- Variable mutation (explicit)
- Conditional execution (if/else)
- Early return from functions/tools
- Pattern matching (match/switch)
- Iteration over collections (for each)
- Loop with break condition

### 7.4 Functions (Lambdas)

- Anonymous functions must be supported for callbacks
- Used primarily with collection operations (filter, map, etc.)

### 7.5 Pipes

- Pipeline operator for chaining transformations
- Enables readable left-to-right data flow

### 7.6 Comments

- Single-line comments must be supported
- Comments must not affect execution
- Comments are for documentation and explanation

### 7.7 Built-in Functions

| Category | Required Functions |
|----------|-------------------|
| Collections | count, first, last, take, skip, reverse, sort, unique, flatten |
| Transformation | map, filter, find, reduce, group |
| Aggregation | sum, average, min, max |
| Text | uppercase, lowercase, trim, split, join, replace, contains, starts with, ends with, length, substring |
| Date/Time | now, today, format date, date arithmetic |
| Type conversion | to number, to string, to boolean, parse JSON, encode JSON |
| Math | absolute, round, floor, ceiling, random |

---

## 8. Observability

### 8.1 Lifecycle Hooks

Agents must support optional hooks:

| Hook | Trigger | Data Available |
|------|---------|----------------|
| Turn start | Before LLM call | Turn number, current messages |
| Tool call | After tool execution | Tool name, arguments, result, duration |
| Error | On any error | Error type, message, context |
| Turn end | After response | Response content, token usage |
| Termination | On agent end | Final state, total turns, duration |

### 8.2 External Observers

- Observers can be attached at runtime (not in agent code)
- Observers receive events for all capability invocations
- Observers receive all lifecycle events
- Multiple observers can be attached simultaneously
- Observers must not affect agent logic or control flow

### 8.3 Tracing

- Every workflow/agent execution must have a unique trace ID
- Trace ID must propagate to all child agents and tool calls
- All events must include trace ID for correlation
- Parent-child relationships must be trackable (workflow → agent → tool)

### 8.4 Audit Trail

Every capability invocation must record:

- Timestamp
- Trace ID (for correlation)
- Capability name
- Operation name
- Input (sanitized if sensitive)
- Output (truncated if large)
- Duration
- Success/failure status
- Error details (if failed)

Sensitive data (API keys, passwords, PII) must be redactable in audit logs.

---

## 9. Error Handling

### 9.1 Error Types

| Type | Source | Recovery |
|------|--------|----------|
| Tool failure | Tool execution error | Retry, fallback, or surface to LLM |
| Capability failure | External system error | Retry with backoff, fail gracefully |
| Validation failure | Invalid parameters | Prevent agent creation, clear message |
| Limit exceeded | Turn limit, token limit | Graceful termination |
| Timeout | Operation too slow | Retry or fail with message |

### 9.2 Error Handling Requirements

- Tool failures must be catchable
- Retry policies must be configurable:
  - Maximum attempts
  - Backoff strategy (none, linear, exponential)
  - Retryable error types
- Fallback responses must be possible
- Errors must surface with clear, actionable messages
- Agent must be able to gracefully degrade (respond with apology vs crash)

### 9.3 Validation

- Initialization phase must support validation logic
- Validation failures must prevent agent creation
- Validation errors must have clear, specific messages

---

## 10. Testing

### 10.1 Mock Capabilities

Every built-in capability must have a mock implementation:

| Capability | Mock Behavior |
|------------|---------------|
| LLM | Return fixed response, or response based on input patterns |
| Database | In-memory store with predefined data, supports all operations |
| HTTP | Return predefined responses based on URL/method patterns |
| Filesystem | In-memory filesystem with predefined file contents |
| Shell | Return predefined outputs based on command patterns |

### 10.2 Mock Requirements

- Mocks must implement the exact same interface as real capabilities
- Mocks must record all invocations (method, arguments, timestamp)
- Mocks must support pattern-based responses (different response for different inputs)
- Mocks must support failure simulation (throw errors on demand)
- Mock state must be inspectable after test execution

### 10.3 Test Assertions

Tests must be able to verify:

- Agent responses (content, format)
- Tool calls (which tools called, with what arguments)
- Capability invocations (database queries, HTTP requests)
- State changes (agent state before/after)
- Error handling (correct errors thrown/caught)

---

## 11. Environment Variables

- Capability configuration must support environment variable references
- Environment variables are resolved at capability instantiation
- Missing required environment variables must cause clear errors
- Sensitive values (API keys) should only be in environment variables, never in code

---

## 12. Safety Requirements

### 12.1 Sandboxing

| Capability | Sandboxing Options |
|------------|-------------------|
| Filesystem | Root directory restriction, read-only mode |
| Shell | Command allowlist, command denylist, no shell expansion option |
| HTTP | Domain allowlist, domain denylist |
| Database | Query restrictions (optional) |

### 12.2 Limits

| Limit | Purpose |
|-------|---------|
| Turn limit | Prevent infinite agent loops |
| Token limit | Prevent context overflow, control costs |
| Timeout | Prevent hung operations |
| Rate limit | Prevent API abuse |

---

## 13. Out of Scope (v1)

The following are explicitly NOT requirements for version 1:

- Multi-file modules (all code in single file)
- Import/export between Manuscript files
- JavaScript/TypeScript interop
- Streaming responses
- Static type annotations
- User-defined capability types
- Distributed execution across machines
- Persistence and checkpointing of agent state
- Hot reloading of agent definitions
- Visual editor or GUI
- Deployment tooling

---

## 14. Success Criteria

The language is successful if:

1. **Readable**: A product manager can read an agent definition and understand what it does
2. **Writable**: An LLM can generate valid agent code reliably (no syntax surprises)
3. **Testable**: All agents can be fully tested with mock capabilities, no external dependencies needed
4. **Observable**: All capability invocations are traceable without code changes
5. **Safe**: Sandboxing, timeouts, and turn limits prevent runaway execution
6. **Composable**: Tools, agents, and workflows combine without friction or special cases
7. **Minimal**: The language has exactly the concepts needed, no more
8. **Consistent**: Same patterns apply everywhere, no exceptions

---

## 15. Glossary

| Term | Definition |
|------|------------|
| Agent | LLM-powered unit that can converse, use tools, and maintain state |
| Capability | Access to an external system (LLM, database, HTTP, filesystem, shell) |
| Conversation | A sequence of messages between user and agent |
| History | The list of messages in a conversation |
| Memory strategy | Function that compacts history to fit within token limits |
| Mock | Fake capability implementation for testing |
| Observer | External component that receives events without affecting logic |
| Prompt | Reusable text template with interpolation |
| Scope | Runtime context that provides capabilities to code within it |
| Service | Stateful object without LLM for data management |
| State | Mutable data belonging to an agent, persists across turns |
| Tool | Function callable by LLM during agent execution |
| Turn | One cycle of: user message → LLM response (may include tool calls) |
| Workflow | Function that orchestrates multiple agents |

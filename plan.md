```markdown
1.  **Modify `internal/grammar/ManuscriptLexer.g4` (Lexer):**
    *   **Revision**: Remove the `@lexer::members { ... }` block entirely from `ManuscriptLexer.g4` as ANTLR's Go target is misplacing these declarations. The fields `parenDepth`, `bracketDepth`, `braceDepth` will be added manually to a custom Go lexer structure.
    *   Lexer actions like `LPAREN: '(' { l.parenDepth++ };` will remain, relying on these fields being available in the custom Go lexer that wraps the ANTLR-generated one. (Actions were updated to use `cl := l.(*CustomManuscriptLexer); ...`)

2.  **Modify `internal/grammar/Manuscript.g4` (Parser):**
    *   Change the `stmt_sep` rule from `stmt_sep: SEMICOLON | NEWLINE;` to `stmt_sep: SEMICOLON;`.
    *   Update parser rules to require mandatory semicolons where they were previously optional.

3.  **Address Specific Newline Allowances (Consequences of the Lexer Change):**
    *   Verification step to confirm behavior for let destructures, function parameters, strings, comments, and keyword/argument newlines based on the implemented changes.

4.  **Create a Custom Go Lexer to Manage State:**
    *   Define a new Go struct (`CustomManuscriptLexer`) in `internal/parser/custom_lexer.go`.
    *   This struct embeds `*parser.ManuscriptLexer` and includes `parenDepth int`, `bracketDepth int`, `braceDepth int`.
    *   Lexer actions in `.g4` will cast the lexer instance to `*CustomManuscriptLexer` to access these fields.
    *   Implement `NewCustomManuscriptLexer` constructor.

5.  **Update Lexer Instantiation:**
    *   Modify compiler/parser setup code (e.g., in `internal/compile/compile.go`) to instantiate `CustomManuscriptLexer`.

6.  **Regenerate Parser and Lexer Code:**
    *   Run `scripts/generate_parser.sh`.

7.  **Testing:**
    *   Execute tests (e.g., in `tests/compilation/newline_semicolon.md` and general suite).
    *   Verify build success and core logic for newline/semicolon handling.

8.  **Create `plan.md` file:**
    *   Create this file documenting the plan.

9.  **Submit the change.**
```

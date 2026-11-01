import StringBuilder from "@std/string.ms"
import TemplatePart, msstd_template_compile from "@std/internal/template.ms"

# Errors from compiling or rendering a plain-text template.
export type TemplateError:
    # A supplied input or output byte budget is negative.
    case InvalidInput
    # The source or rendered UTF-8 text exceeds the supplied byte budget.
    case LimitExceeded
    # Invalid template syntax, with its cause and zero-based UTF-8 source position.
    case Syntax(
        # Diagnostic with source text, byte position, and one-based line and scalar column.
        message: String
    )
    # A named value is absent. An empty string is a present value.
    case MissingVariable(
        # The exact trimmed key required by this placeholder.
        name: String,
        # Zero-based UTF-8 offset of the key in the original template source.
        offset: Int
    )

# A runtime-loaded plain-text template parsed once and reusable with different values.
# Keys inside braces are trimmed and looked up literally; punctuation never invokes code.
# Example: let greeting = try compile("Hello \{name\}!"); try greeting.render({"name": "Ada"}).
# This performs no HTML escaping or context-sensitive validation.
export opaque type Template:
    # Owned compiled pieces; hidden outside this module and reused without reparsing.
    parts: List[TemplatePart]

impl Template:
    # Substitutes named strings verbatim, without reparsing inserted text. Extra values are ignored.
    # A supplied max_bytes bounds UTF-8 output before each append; none or omission adds no budget.
    # The first missing key or exceeded budget in source order is returned, without partial output.
    fn render(values: Map[String, String], max_bytes: Int?) String!TemplateError:
        if let limit = max_bytes:
            if limit < 0: return error(TemplateError.InvalidInput)

        var output = StringBuilder()
        var size = 0

        for part in self.parts:
            if part.variable != 0:
                if let text = values.get(part.text):
                    size = try append(var output, text, size, max_bytes)
                else: return error(
                    TemplateError.MissingVariable(
                        part.text.clone(), part.offset
                    )
                )
            else:
                size = try append(var output, part.text, size, max_bytes)

        return ok(output.build())

fn append(var output: StringBuilder, text: String, size: Int, max_bytes: Int?) Int!TemplateError:
    let bytes = text.byte_length()
    if let limit = max_bytes:
        if bytes > limit - size: return error(TemplateError.LimitExceeded)
    output.append(text)
    return ok(size + bytes)

# Parses runtime text using {name} placeholders; whitespace around a key is trimmed.
# Escape literal braces with backslashes (\{ and \}); \\ emits one backslash.
# Empty keys, unmatched braces and other backslash escapes are syntax errors.
# max_bytes optionally bounds UTF-8 source bytes before parsing; none or omission adds no budget.
export fn compile(source: String, max_bytes: Int?) Template!TemplateError:
    if let limit = max_bytes:
        if limit < 0: return error(TemplateError.InvalidInput)
        if source.byte_length() > limit: return error(TemplateError.LimitExceeded)

    let {parts, diagnostic} = msstd_template_compile(source)
    if not diagnostic.is_empty(): return error(TemplateError.Syntax(diagnostic))

    return ok(Template(parts))

impl Error for TemplateError:
    # Returns a template diagnostic, preserving syntax positions and missing key offsets.
    fn message() String:
        match self:
            InvalidInput: return "template: byte budget must be nonnegative"
            LimitExceeded: return "template: byte budget exceeded"
            Syntax(message): return "template: {message}"
            MissingVariable(name, offset): return "template: missing variable '{name}' at byte {offset}"
# Runtime plain-text templates
# Compile text loaded at runtime with `compile`, then call `Template.render` for each map of values.
# `{name}` substitutes one exact map key. `\{`, `\}` and `\\` emit literal delimiters and backslashes.
# Values are plain text and are never parsed again. Templates cannot execute expressions, call methods,
# include files or access host services. They do not provide context-sensitive HTML safety.
# Supply `max_bytes` to compile or render when source or output needs a byte budget.

export type TemplatePart:
    variable: Int
    text: String
    offset: Int

export type TemplateCompilation:
    parts: List[TemplatePart]
    diagnostic: String

export extern fn msstd_template_compile(source: String) TemplateCompilation

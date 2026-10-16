import parse_timestamp from "@std/time.ms"
import parse from "@std/url.ms"
import parse_float from "@std/numbers.ms"
import JsonValue from "@std/json.ms"
import AgentError from "./types.ms"
import copy_json from "./transcript.ms"
import compile from "@std/regex.ms"
import floor from "@std/math.ms"

type SchemaContext:
    schema: JsonValue
    formats: Map[String, fn(value: String) -> Bool]

export fn field(value: JsonValue, name: String) -> Optional[JsonValue]:
    match value:
        ObjectValue(values): return values.get(name)
        _: return none

export fn text(value: JsonValue) -> String:
    match value:
        StringValue(value): return value
        NumberValue(value): return value
        _: return ""

export fn array(value: JsonValue) -> List[JsonValue]:
    match value:
        ArrayValue(values): return values
        _: return []

fn number(value: JsonValue) -> Float:
    return parse_float(text(value)).unwrap_or(0.0)

fn fail(path: String, message: String) -> Result[JsonValue, Error]:
    return error(AgentError.InvalidState("{path}: {message}"))

fn type_matches(value: JsonValue, kind: String) -> Bool:
    match value:
        Null: return kind == "null"
        BoolValue(_): return kind == "boolean"
        StringValue(_): return kind == "string"
        NumberValue(value):
            let parsed = parse_float(value)
            return (
                parsed.is_ok
                and (
                    kind == "number"
                    or (
                        kind == "integer"
                        and floor(
                            parsed.unwrap()
                        ) == parsed.unwrap()
                    )
                )
            )
        ArrayValue(_): return kind == "array"
        ObjectValue(_): return kind == "object"

fn coerce(value: JsonValue, kind: String) -> JsonValue:
    if type_matches(value, kind): return value

    if kind == "number" or kind == "integer":
        if value == JsonValue.Null: return JsonValue.NumberValue("0")
        if value == JsonValue.BoolValue(true): return JsonValue.NumberValue("1")
        if value == JsonValue.BoolValue(false): return JsonValue.NumberValue("0")

        let parsed = parse_float(text(value).trim())

        if parsed.is_ok and parsed.unwrap().is_finite:
            let candidate = JsonValue.NumberValue(parsed.unwrap().toString())
            if type_matches(candidate, kind): return candidate

    if kind == "boolean":
        if (
            value == JsonValue.StringValue("true")
            or value == JsonValue.NumberValue("1")
        ): return JsonValue.BoolValue(true)
        if (
            value == JsonValue.StringValue("false")
            or value == JsonValue.NumberValue("0")
            or value == JsonValue.Null
        ): return JsonValue.BoolValue(false)

    if kind == "string":
        if value == JsonValue.Null: return JsonValue.StringValue("")

        match value:
            NumberValue(value): return JsonValue.StringValue(value)
            BoolValue(value): return JsonValue.StringValue(value.toString())
            _: return value

    if (
        kind == "null"
        and (
            value == JsonValue.StringValue("")
            or value == JsonValue.NumberValue("0")
            or value == JsonValue.BoolValue(false)
        )
    ):
        return JsonValue.Null

    return value

# JSON numeric identity uses Number semantics, including 1 == 1.0.
fn equal_json(left: JsonValue, right: JsonValue) -> Bool:
    match left:
        NumberValue(_):
            if type_matches(right, "number"): return number(left) == number(right)

            return false
        ArrayValue(values): return equal_array(values, right)
        ObjectValue(values): return equal_object(values, right)
        _: return left == right

fn equal_array(left: List[JsonValue], right: JsonValue) -> Bool:
    let values = match right:
        ArrayValue(values): values
        _: return false

    if left.length != values.length: return false

    for entry in left.entries():
        if not equal_json(entry.value, values[entry.index].unwrap()): return false

    return true

fn equal_object(left: Map[String, JsonValue], right: JsonValue) -> Bool:
    let values = match right:
        ObjectValue(values): values
        _: return false

    if left.length != values.length: return false

    for entry in left.entries():
        if not values.contains(entry.key): return false
        if not equal_json(entry.value, values.get(entry.key).unwrap()): return false

    return true

export fn validate_arguments(
    schema: JsonValue,
    value: JsonValue,
    formats: Map[String, fn(value: String) -> Bool] = Map[
        String,
        fn(value: String) -> Bool
    ]()
) -> Result[JsonValue, Error]:
    let copy = try copy_json(value)
    # Null is the legacy explicit-validator-only declaration.
    if schema == JsonValue.Null: return ok(copy)

    return visit(
        schema: schema,
        input: copy,
        root: SchemaContext(schema, formats),
        path: "root",
        depth: 0,
        convert: true
    )

export fn validate_output(
    schema: JsonValue,
    value: JsonValue,
    formats: Map[String, fn(value: String) -> Bool] = Map[
        String,
        fn(value: String) -> Bool
    ]()
) -> Result[JsonValue, Error]:
    return visit(
        schema: schema,
        input: try copy_json(value),
        root: SchemaContext(schema, formats),
        path: "root",
        depth: 0,
        convert: false
    )

fn reference(root: JsonValue, pointer: String) -> Result[JsonValue, Error]:
    if pointer == "#": return ok(root)
    if not pointer.starts_with("#/"): return fail(
        "schema",
        "only local JSON references are supported"
    )

    var current = root

    for part in pointer.slice(2, pointer.scalar_length).unwrap().split("/"):
        let key = (try part.replace_all("~1", "/")).replace_all("~0", "~").unwrap()
        let next = field(current, key)
        if next.is_none: return fail("schema", "unresolved reference {pointer}")

        current = next.unwrap()

    return ok(current)

fn union(
    schemas: List[JsonValue],
    value: JsonValue,
    root: SchemaContext,
    path: String,
    depth: Int,
    convert: Bool,
    exactly_one: Bool
) -> Result[JsonValue, Error]:
    var matches = 0
    var selected = value

    for schema in schemas:
        let result = visit(schema, value, root, path, depth + 1, false)

        if result.is_ok:
            matches = matches + 1
            selected = result.unwrap()

    if matches == 0 and convert:
        for schema in schemas:
            let result = visit(schema, value, root, path, depth + 1, true)

            if result.is_ok:
                selected = result.unwrap()
                break

        for schema in schemas:
            if visit(schema, selected, root, path, depth + 1, false).is_ok: matches = (
                matches
                + 1
            )

    if matches == 0 or (exactly_one and matches != 1): return fail(
        path,
        "union schema did not match"
    )

    return ok(selected)

fn visit(
    schema: JsonValue,
    input: JsonValue,
    root: SchemaContext,
    path: String,
    depth: Int,
    convert: Bool
) -> Result[JsonValue, Error]:
    if depth > 128: return fail(path, "schema nesting exceeds 128")
    if schema == JsonValue.BoolValue(true): return ok(input)
    if schema == JsonValue.BoolValue(false): return fail(
        path,
        "schema rejects this value"
    )

    let rules = match schema:
        ObjectValue(values): values
        _: return fail("schema", "expected an object or boolean schema")

    let supported = [
        "$schema",
        "$id",
        "$ref",
        "$defs",
        "definitions",
        "title",
        "description",
        "default",
        "examples",
        "deprecated",
        "readOnly",
        "writeOnly",
        "type",
        "enum",
        "const",
        "allOf",
        "anyOf",
        "oneOf",
        "not",
        "if",
        "then",
        "else",
        "properties",
        "required",
        "additionalProperties",
        "patternProperties",
        "propertyNames",
        "dependentRequired",
        "minProperties",
        "maxProperties",
        "items",
        "prefixItems",
        "additionalItems",
        "minItems",
        "maxItems",
        "uniqueItems",
        "contains",
        "minContains",
        "maxContains",
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "multipleOf",
        "minLength",
        "maxLength",
        "pattern",
        "format"
    ]

    for key in rules.keys():
        if not supported.contains(key): return fail(
            "schema",
            "unsupported keyword {key}"
        )

    var value = input

    if rules.contains("$ref"):
        value = try visit(
            try reference(root.schema, text(rules.get("$ref").unwrap())),
            value,
            root,
            path,
            (depth + 1),
            convert
        )

    for sub in array(rules.get_or("allOf", JsonValue.Null)):
        value = try visit(sub, value, root, path, depth + 1, convert)

    if rules.contains("anyOf"): value = try union(
        array(rules.get("anyOf").unwrap()),
        value,
        root,
        path,
        depth,
        convert,
        false
    )

    if rules.contains("oneOf"): value = try union(
        array(rules.get("oneOf").unwrap()),
        value,
        root,
        path,
        depth,
        convert,
        true
    )

    if (
        rules.contains("not")
        and visit(
            rules.get("not").unwrap(),
            value,
            root,
            path,
            (depth + 1),
            false
        ).is_ok
    ): return fail(path, "matches forbidden schema")

    if rules.contains("if"):
        var branch = "else"

        if visit(rules.get("if").unwrap(), value, root, path, depth + 1, false).is_ok: branch = "then"

        if rules.contains(branch): value = try visit(
            rules.get(branch).unwrap(),
            value,
            root,
            path,
            (depth + 1),
            convert
        )

    if rules.contains("type"):
        let declared = rules.get("type").unwrap()
        var types = array(declared)

        if types.is_empty: types = [declared]

        if not types.some(fn(kind: JsonValue) -> Bool: type_matches(value, text(kind))):
            if convert:
                for kind in types:
                    let candidate = coerce(value, text(kind))

                    if type_matches(candidate, text(kind)):
                        value = candidate
                        break

            if not types.some(
                fn(kind: JsonValue) -> Bool: type_matches(
                    value,
                    text(kind)
                )
            ): return fail(path, "expected {declared}")

    if rules.contains("const") and not equal_json(value, rules.get("const").unwrap()): return fail(
        path,
        "value differs from const"
    )
    if (
        rules.contains("enum")
        and not array(rules.get("enum").unwrap()).some(
            fn(candidate: JsonValue) -> Bool: equal_json(candidate, value)
        )
    ): return fail(path, "value is outside enum")

    match value:
        ObjectValue(values): return object_value(
            rules,
            values,
            root,
            path,
            depth,
            convert
        )
        ArrayValue(values): return array_value(
            rules,
            values,
            root,
            path,
            depth,
            convert
        )
        StringValue(value): return string_value(rules, value, path, root)
        NumberValue(_): return numeric_value(rules, value, path)
        _: return ok(value)

fn within(
    rules: Map[String, JsonValue],
    minimum: String,
    maximum: String,
    size: Int
) -> Bool:
    if (
        rules.contains(minimum)
        and size.to_float() < number(rules.get(minimum).unwrap())
    ): return false
    if (
        rules.contains(maximum)
        and size.to_float() > number(rules.get(maximum).unwrap())
    ): return false

    return true

fn string_value(
    rules: Map[String, JsonValue],
    value: String,
    path: String,
    root: SchemaContext
) -> Result[JsonValue, Error]:
    if not within(rules, "minLength", "maxLength", value.scalar_length): return fail(
        path,
        "string length is outside schema bounds"
    )

    if rules.contains("pattern"):
        let pattern = try compile(text(rules.get("pattern").unwrap()))
        if not pattern.matches(value): return fail(
            path,
            "string does not match pattern"
        )

    if rules.contains("format"):
        let name = text(rules.get("format").unwrap())
        let custom = root.formats.get(name)

        if custom.is_some:
            if not custom.unwrap()(value): return fail(path, "invalid {name} format")
        else:
            let valid = try builtin_format(name, value)
            if not valid: return fail(path, "invalid {name} format")

    return ok(JsonValue.StringValue(value))

fn numeric_value(
    rules: Map[String, JsonValue],
    value: JsonValue,
    path: String
) -> Result[JsonValue, Error]:
    let actual = number(value)
    if rules.contains("minimum") and actual < number(rules.get("minimum").unwrap()): return fail(
        path,
        "below minimum"
    )
    if rules.contains("maximum") and actual > number(rules.get("maximum").unwrap()): return fail(
        path,
        "above maximum"
    )
    if (
        rules.contains("exclusiveMinimum")
        and actual <= number((rules.get("exclusiveMinimum").unwrap()))
    ): return fail(path, "below exclusive minimum")
    if (
        rules.contains("exclusiveMaximum")
        and actual >= number((rules.get("exclusiveMaximum").unwrap()))
    ): return fail(path, "above exclusive maximum")

    if rules.contains("multipleOf"):
        let divisor = number(rules.get("multipleOf").unwrap())
        if divisor <= 0.0: return fail("schema", "multipleOf must be positive")

        let ratio = actual / divisor
        if ratio != floor(ratio): return fail(path, "not a multipleOf value")

    return ok(value)

fn object_value(
    rules: Map[String, JsonValue],
    values: Map[String, JsonValue],
    root: SchemaContext,
    path: String,
    depth: Int,
    convert: Bool
) -> Result[JsonValue, Error]:
    let properties = rules.get_or("properties", JsonValue.Null)
    let patterns = rules.get_or("patternProperties", JsonValue.Null)
    let required = array(rules.get_or("required", JsonValue.Null))
    let result = Map[String, JsonValue]()

    for entry in values.entries():
        var value = entry.value
        let property = field(properties, entry.key)

        if (
            convert
            and value == JsonValue.Null
            and property.is_some
            and not required.contains(JsonValue.StringValue(entry.key))
            and field(property.unwrap(), "$ref").is_none
        ):
            if visit(property.unwrap(), value, root, path, depth + 1, false).is_error: continue

        var matched = false

        if property.is_some:
            value = try visit(
                property.unwrap(),
                value,
                root,
                "{path}.{entry.key}",
                (depth + 1),
                convert
            )
            matched = true

        let pattern_entries = match patterns:
            ObjectValue(patterns): patterns.entries()
            _: []

        for pattern in pattern_entries:
            let regex = try compile(pattern.key)

            if regex.matches(entry.key):
                value = try visit(
                    pattern.value,
                    value,
                    root,
                    "{path}.{entry.key}",
                    (depth + 1),
                    convert
                )
                matched = true

        if not matched and rules.contains("additionalProperties"):
            value = try visit(
                rules.get("additionalProperties").unwrap(),
                value,
                root,
                "{path}.{entry.key}",
                (depth + 1),
                convert
            )

        if rules.contains("propertyNames"):
            let _name = try visit(
                rules.get("propertyNames").unwrap(),
                JsonValue.StringValue(entry.key),
                root,
                path,
                (depth + 1),
                false
            )

        result.add(entry.key, value)

    for key in required:
        if not result.contains(text(key)): return fail(
            "{path}.{text(key)}",
            "required property is missing"
        )

    if not within(rules, "minProperties", "maxProperties", result.length): return fail(
        path,
        "object size is outside schema bounds"
    )

    let dependencies = rules.get_or("dependentRequired", JsonValue.Null)

    for key in result.keys():
        for needed in array(field(dependencies, key).unwrap_or(JsonValue.Null)):
            if not result.contains(text(needed)): return fail(
                path,
                "missing dependent property {text(needed)}"
            )

    return ok(JsonValue.ObjectValue(result))

fn array_value(
    rules: Map[String, JsonValue],
    values: List[JsonValue],
    root: SchemaContext,
    path: String,
    depth: Int,
    convert: Bool
) -> Result[JsonValue, Error]:
    if not within(rules, "minItems", "maxItems", values.length): return fail(
        path,
        "array length is outside schema bounds"
    )

    let result: List[JsonValue] = []
    let items = rules.get_or("items", JsonValue.BoolValue(true))
    let prefix = rules.contains("prefixItems")

    let legacy = match items:
        ArrayValue(_): true
        _: false

    var tuple = array(rules.get_or("prefixItems", JsonValue.Null))

    if not prefix: tuple = array(items)

    var tail = rules.get_or("additionalItems", JsonValue.BoolValue(true))

    if prefix: tail = items

    for entry in values.entries():
        var schema = items

        if prefix or legacy:
            schema = tuple[entry.index].unwrap_or(tail)

        result.append(
            try visit(
                schema,
                entry.value,
                root,
                "{path}[{entry.index}]",
                (depth + 1),
                convert
            )
        )

    if rules.get_or("uniqueItems", JsonValue.Null) == JsonValue.BoolValue(true):
        var index = 0

        for value in result:
            if (
                result
                .take(index)
                .some(
                    fn(candidate: JsonValue) -> Bool: equal_json(
                        candidate,
                        value
                    )
                )
            ): return fail(path, "duplicate array value")

            index = index + 1

    if rules.contains("contains"):
        let count = result.count(
            fn(value: JsonValue) -> Bool: visit(
                (rules.get("contains").unwrap()),
                value,
                root,
                path,
                (depth + 1),
                false
            ).is_ok
        )
        var minimum = 1.0

        if rules.contains("minContains"): minimum = number(
            (rules.get("minContains").unwrap())
        )

        if count.to_float() < minimum: return fail(path, "too few contains matches")
        if (
            rules.contains("maxContains")
            and count.to_float() > number(
                (rules.get("maxContains").unwrap())
            )
        ): return fail(path, "too many contains matches")

    return ok(JsonValue.ArrayValue(result))

fn builtin_format(name: String, value: String) -> Result[Bool, Error]:
    if name == "date-time": return ok(parse_timestamp(value).is_ok)
    if name == "date": return ok(
        (
            value.scalar_length == 10
            and parse_timestamp("{value}T00:00:00Z").is_ok
        )
    )
    if name == "time": return ok(parse_timestamp("1970-01-01T{value}").is_ok)
    if name == "regex": return ok(compile(value).is_ok)

    if name == "uri" or name == "uri-reference":
        let url = parse(value)
        if url.is_error: return ok(false)

        return ok(name == "uri-reference" or url.unwrap().scheme != "")

    var pattern = ""

    if name == "email": pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
    else if name == "uuid": pattern = "^[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}$"
    else if name == "hostname": pattern = "^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\\.)*[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\\.?$"
    else if name == "ipv4":
        let parts = value.split(".")
        if parts.length != 4: return ok(false)

        for part in parts:
            let number = part.parse_int()
            if (number.is_none or number.unwrap() < 0 or number.unwrap() > 255): return ok(
                false
            )
            if part != number.unwrap().toString(): return ok(false)

        return ok(true)
    else: return error(
        AgentError.InvalidState(
            "schema: unsupported format {name}; supply a native format predicate"
        )
    )

    return ok((try compile(pattern)).matches(value))

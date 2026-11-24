+++
title = "YAML and XML"
weight = 7
+++

# YAML and XML

Read configuration from YAML and documents from XML. Both parsers are written in Manuscript and return plain values you match on, so malformed input is an error you handle.

## Read a YAML setting

Save as `settings.ms`. One small function per `match` keeps the flow flat. `parse` returns a `YamlValue`: `ObjectValue` for a mapping, `ArrayValue` for a sequence, and `StringValue`, `BoolValue`, `NumberValue` or `Null` for scalars. A number keeps its original text, so nothing is rounded before you choose how to read it. `get` on a map returns an optional, and `get_or(Null)` turns a missing key into `Null`.

<!-- manuscript-example: {"mode":"run","stdout":"port 8080\n"} -->
```manuscript
import YamlValue, parse from "@std/data/yaml.ms"

fn number_text(value YamlValue) String {
    match value {
        NumberValue(text) => return text.clone()
        _ => return "not a number"
    }
}

fn port_of(doc YamlValue) String {
    match doc {
        ObjectValue(fields) => return number_text(fields.get("port") or Null)
        _ => return "not a mapping"
    }
}

fn main() Void! {
    doc := parse("name: api\nport: 8080\ntags:\n  - web\n  - internal\n")?
    print(f"port {port_of(doc)}")
}
```

- `parse_all` reads a file with several `---` documents. `stringify` writes a value back.
- The parser reads configuration YAML: aliases and anchors work, tags other than `!!str` are ignored, and a mapping key that is a sequence or mapping is an error.
- To read YAML into your own type, convert the `YamlValue` by hand as above. For JSON, `parse[T]` reads straight into a type ([Numbers and JSON](text-and-data.md)).

## Read an XML document

Save as `feed.ms`. `parse` returns the root `XmlNode`. `find_all` lists the matching child elements, `attribute` returns an optional, and `text` joins the character data below a node with entities such as `&amp;` already decoded.

<!-- manuscript-example: {"mode":"run","stdout":"1: Hi & bye\n2: Bye\n"} -->
```manuscript
import parse from "@std/data/xml.ms"

fn main() Void! {
    doc := parse(
        "<feed><item id=\"1\">Hi &amp; bye</item><item id=\"2\">Bye</item></feed>"
    )?
    for item in doc.find_all("item") {
        print(f"{item.attribute("id") or "?"}: {item.text()}")
    }
}
```

- A DOCTYPE is skipped and no entity it defines is expanded, so a hostile document cannot pull in files or grow without bound. `max_depth` bounds nesting.
- Namespaces are not resolved: a name keeps its prefix as written (`svg:rect`).
- `stringify(node, indent)` writes a tree back with escaping; `escape_text` and `escape_attribute` escape a single value.

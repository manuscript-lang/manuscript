// expect-debug: allocs=21 alloc_bytes=70053
// expect-release: allocs=21 alloc_bytes=70053
// Compact output skips the text-classification copy; mixed content stops inspecting
// later siblings.
import XmlNode, stringify from "@std/data/xml.ms"

export fn main() Int {
	text := "x".repeat(4096)
	root := XmlNode.XmlElement("root", [], [XmlNode.XmlText(text.clone())])
	if stringify(root) != f"<root>{text}</root>" { return 1 }

	mixed := XmlNode.XmlElement("root", [], [XmlNode.XmlText("text"), root.clone()])
	if stringify(mixed, "  ") != f"<root>text<root>{text}</root></root>\n" { return 2 }

	return 0
}

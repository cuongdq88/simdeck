import Foundation

/// One accessibility node from `uiautomator dump`, in normalized coordinates.
/// Android only: the iOS simulator path has no accessibility tree reader.
struct UiElement {
  let label: String
  let id: String
  let value: String
  let role: String
  /// left, top, right, bottom in 0…1 of the screen.
  let frame: [Double]
  let center: (x: Double, y: Double)

  var json: [String: Any] {
    [
      "label": label, "id": id, "value": value, "role": role,
      "x": center.x, "y": center.y, "frame": frame,
    ]
  }

  /// Exact match on label, id or value first, then a substring one.
  static func matches(_ element: UiElement, _ query: String) -> Bool {
    let q = query.lowercased()
    return [element.label, element.id, element.value].contains {
      $0.lowercased() == q
    }
  }

  static func contains(_ element: UiElement, _ query: String) -> Bool {
    let q = query.lowercased()
    return [element.label, element.id, element.value].contains {
      !$0.isEmpty && $0.lowercased().contains(q)
    }
  }
}

enum UiAutomation {
  /// `uiautomator dump` writes to a file on the device; read it back.
  static func elements(serial: String) async -> [UiElement] {
    let dump = await AdbService.shell(
      serial: serial, ["uiautomator", "dump", "/sdcard/window_dump.xml"], timeout: 60)
    guard dump.ok else { return [] }
    let cat = await AdbService.shell(
      serial: serial, ["cat", "/sdcard/window_dump.xml"], timeout: 30)
    guard cat.ok else { return [] }
    let nodes = parse(cat.stdout)
    guard
      let width = nodes.compactMap({ $0.rect?.2 }).max(),
      let height = nodes.compactMap({ $0.rect?.3 }).max(),
      width > 0, height > 0
    else { return [] }
    return nodes.compactMap { node in
      guard let rect = node.rect, rect.2 > rect.0, rect.3 > rect.1 else { return nil }
      return UiElement(
        label: node.text.isEmpty ? node.desc : node.text,
        id: node.id,
        value: node.text.isEmpty ? "" : node.desc,
        role: node.cls.split(separator: ".").last.map(String.init) ?? node.cls,
        frame: [rect.0 / width, rect.1 / height, rect.2 / width, rect.3 / height],
        center: (
          x: (rect.0 + rect.2) / 2 / width,
          y: (rect.1 + rect.3) / 2 / height
        ))
    }
  }

  /// The element `label` names, in screen order; -1 picks the last.
  static func locate(
    label: String, index: Int, in elements: [UiElement]
  ) -> UiElement? {
    var hits = elements.filter { UiElement.matches($0, label) }
    if hits.isEmpty {
      hits = elements.filter { UiElement.contains($0, label) }
    }
    guard !hits.isEmpty else { return nil }
    return hits[index < 0 ? hits.count - 1 : min(index, hits.count - 1)]
  }

  private struct Node {
    var text = ""
    var desc = ""
    var id = ""
    var cls = ""
    var rect: (Double, Double, Double, Double)?
  }

  private static func parse(_ xml: String) -> [Node] {
    guard let data = xml.data(using: .utf8) else { return [] }
    let parser = DumpParser()
    let xmlParser = XMLParser(data: data)
    xmlParser.delegate = parser
    xmlParser.parse()
    return parser.nodes
  }

  private final class DumpParser: NSObject, XMLParserDelegate {
    var nodes: [Node] = []

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes: [String: String] = [:]
    ) {
      guard name == "node" else { return }
      nodes.append(
        Node(
          text: attributes["text"] ?? "", desc: attributes["content-desc"] ?? "",
          id: attributes["resource-id"] ?? "", cls: attributes["class"] ?? "",
          rect: Self.rect(attributes["bounds"])))
    }

    /// `[0,0][1080,2400]`.
    private static func rect(_ bounds: String?) -> (Double, Double, Double, Double)? {
      guard let bounds else { return nil }
      let numbers = bounds
        .split(whereSeparator: { $0 == "[" || $0 == "]" || $0 == "," })
        .compactMap { Double($0) }
      guard numbers.count == 4 else { return nil }
      return (numbers[0], numbers[1], numbers[2], numbers[3])
    }
  }
}

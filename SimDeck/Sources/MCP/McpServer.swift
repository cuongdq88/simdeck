import Foundation
import Network

/// A loopback MCP server (Streamable HTTP, JSON responses) so agents can
/// drive the same devices the window shows.
@MainActor
final class McpServer {
  private weak var model: AppModel?
  private let port: UInt16
  private var listener: NWListener?
  private let sessionID = UUID().uuidString
  private static let queue = DispatchQueue(label: "dev.simdeck.mcp", qos: .userInitiated)

  private(set) var running = false
  private(set) var error: String?
  var onChange: (() -> Void)?

  init(model: AppModel, port: UInt16) {
    self.model = model
    self.port = port
  }

  func start() {
    guard listener == nil else { return }
    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.requiredLocalEndpoint = .hostPort(
        host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          switch state {
          case .ready:
            self.running = true
            self.error = nil
          case .failed(let failure):
            self.running = false
            self.error = failure.localizedDescription
          default:
            break
          }
          self.onChange?()
        }
      }
      listener.start(queue: Self.queue)
      self.listener = listener
    } catch {
      running = false
      self.error = error.localizedDescription
      onChange?()
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    running = false
    onChange?()
  }

  var url: String { "http://127.0.0.1:\(port)/mcp" }

  // MARK: - HTTP

  private nonisolated func accept(_ connection: NWConnection) {
    connection.start(queue: Self.queue)
    receive(connection, buffer: Data())
  }

  private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
      [weak self] data, _, isComplete, error in
      var buffer = buffer
      if let data { buffer.append(data) }
      guard let self else {
        connection.cancel()
        return
      }
      if let request = HttpRequest.parse(buffer) {
        Task { @MainActor in
          let response = await self.handle(request)
          connection.send(
            content: response,
            completion: .contentProcessed { _ in connection.cancel() })
        }
      } else if isComplete || error != nil || buffer.count > 4 << 20 {
        connection.cancel()
      } else {
        self.receive(connection, buffer: buffer)
      }
    }
  }

  @MainActor
  private func handle(_ request: HttpRequest) async -> Data {
    guard request.method == "POST" else {
      return http(status: "405 Method Not Allowed", body: Data())
    }
    guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
    else {
      return rpcError(nil, -32700, "Parse error")
    }

    if let method = object["method"] as? String, method.hasPrefix("notifications/") {
      return http(status: "202 Accepted", body: Data())
    }

    let method = object["method"] as? String ?? ""
    let id = object["id"]
    let params = object["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
      return rpcResult(
        id,
        [
          "protocolVersion": "2025-06-18",
          "capabilities": ["tools": [String: Any]()],
          "serverInfo": ["name": "simdeck", "version": "1.0.0"],
        ],
        extraHeaders: ["Mcp-Session-Id": sessionID])
    case "ping":
      return rpcResult(id, [:])
    case "tools/list":
      return rpcResult(id, ["tools": Self.tools])
    case "tools/call":
      let name = params["name"] as? String ?? ""
      let arguments = params["arguments"] as? [String: Any] ?? [:]
      do {
        let text = try await callTool(name, arguments)
        return rpcResult(id, [
          "content": [["type": "text", "text": text]],
          "isError": false,
        ])
      } catch {
        return rpcResult(id, [
          "content": [["type": "text", "text": error.localizedDescription]],
          "isError": true,
        ])
      }
    default:
      return rpcError(id, -32601, "Method not found: \(method)")
    }
  }

  private func rpcResult(
    _ id: Any?, _ result: [String: Any], extraHeaders: [String: String] = [:]
  ) -> Data {
    let payload: [String: Any] = [
      "jsonrpc": "2.0",
      "id": id ?? NSNull(),
      "result": result,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
      return http(status: "500 Internal Server Error", body: Data())
    }
    return http(body: data, extraHeaders: extraHeaders)
  }

  private func rpcError(_ id: Any?, _ code: Int, _ message: String) -> Data {
    let payload: [String: Any] = [
      "jsonrpc": "2.0",
      "id": id ?? NSNull(),
      "error": ["code": code, "message": message],
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return http(body: data)
  }

  private func http(
    status: String = "200 OK", body: Data, extraHeaders: [String: String] = [:]
  ) -> Data {
    var head = [
      "HTTP/1.1 \(status)",
      "Content-Type: application/json",
      "Content-Length: \(body.count)",
      "Connection: close",
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Headers: content-type, mcp-session-id",
      "Access-Control-Expose-Headers: mcp-session-id",
    ]
    for (key, value) in extraHeaders {
      head.append("\(key): \(value)")
    }
    var data = Data((head.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    data.append(body)
    return data
  }

  // MARK: - Tools

  @MainActor
  private func callTool(_ name: String, _ arguments: [String: Any]) async throws -> String {
    guard let model else { throw McpToolError.message("The app is shutting down.") }

    switch name {
    case "list_devices":
      let list = model.devices.map { device in
        [
          "id": device.key,
          "name": device.name,
          "os": device.os.rawValue,
          "kind": device.kind.rawValue,
          "state": device.state.rawValue,
          "platform": device.platform,
          "streaming": model.isStreaming(device),
        ] as [String: Any]
      }
      return json(["devices": list])

    case "get_device_catalogs":
      let images = model.images.map { image in
        [
          "package": image.packageId,
          "api": image.api,
          "tag": image.tag,
          "abi": image.abi,
        ] as [String: Any]
      }
      let profiles = HardwareProfiles.all.map { profile in
        [
          "id": profile.id,
          "name": profile.name,
          "width": profile.width,
          "height": profile.height,
          "density": profile.density,
        ] as [String: Any]
      }
      return json(["system_images": images, "hardware_profiles": profiles])

    case "create_avd":
      let name = try required("name", arguments)
      let image = try selectedImage(arguments, model: model)
      let profile = HardwareProfiles.profile(
        id: arguments["profile"] as? String ?? "") ?? HardwareProfiles.all.first!
      let form = AvdCreateForm(
        name: name,
        profile: profile,
        image: image,
        ramMb: arguments["ram_mb"] as? Int ?? 2048,
        storage: arguments["storage"] as? String ?? "8G",
        cameraBack: arguments["camera"] as? String ?? "virtualscene",
        cameraFront: "none",
        orientation: arguments["orientation"] as? String ?? "portrait",
        keyboard: arguments["keyboard"] as? Bool ?? true)
      try await model.createAndroid(form)
      return json(["created": name, "image": image.packageId])

    case "create_simulator":
      let name = try required("name", arguments)
      let types = await SimctlService.deviceTypes()
      let runtimes = await SimctlService.runtimes()
      let type = types.first { $0.id == (arguments["device_type"] as? String ?? "") }
        ?? types.first
      let runtime = runtimes.first { $0.id == (arguments["runtime"] as? String ?? "") }
        ?? runtimes.first
      guard let type, let runtime else {
        throw McpToolError.message("No simulator device type or runtime is installed.")
      }
      try await model.createSimulator(
        name: name, deviceTypeID: type.id, runtimeID: runtime.id)
      return json(["created": name, "device_type": type.id, "runtime": runtime.id])

    case "start_device":
      let device = try findDevice(arguments, model: model)
      let headless = arguments["headless"] as? Bool ?? true
      let stream = arguments["stream"] as? Bool ?? true
      let coldBoot = arguments["cold_boot"] as? Bool
      await model.start(
        device, coldBoot: coldBoot, headless: headless, stream: stream)
      await model.refresh()
      guard model.devices.first(where: { $0.key == device.key })?.isRunning == true
      else {
        throw McpToolError.message(
          model.errorMessage ?? "Could not start \(device.name).")
      }
      if stream, model.session(for: device) == nil {
        throw McpToolError.message(
          model.sessionErrors[device.key] ?? "The stream did not start.")
      }
      return json([
        "started": device.name, "headless": headless, "stream": stream,
      ])

    case "stream_device":
      let device = try findDevice(arguments, model: model)
      await model.openStream(device)
      return json(["streaming": device.name])

    case "record_grid":
      let quality = GridRecordQuality(
        rawValue: arguments["quality"] as? String ?? "") ?? model.gridQuality
      let wasRecording = model.isGridRecording
      let saved = await model.toggleGridRecording(quality: quality)
      if wasRecording {
        guard let saved else {
          throw McpToolError.message(
            model.errorMessage ?? "Could not finish the grid recording.")
        }
        return json(["saved": saved.path])
      }
      guard model.isGridRecording, let url = model.gridRecordingURL else {
        throw McpToolError.message(
          model.errorMessage ?? "Could not record the grid.")
      }
      return json(["recording": "grid", "quality": quality.rawValue, "path": url.path])

    case "get_spotlight":
      let focus = model.layout == .grid ? nil : model.spotlightKey
      var focusValue: Any = NSNull()
      if let key = focus, let device = model.devices.first(where: { $0.key == key }) {
        focusValue = ["id": device.key, "name": device.name]
      }
      let streams = model.openDevices.map { device -> [String: Any] in
        [
          "id": device.key,
          "name": device.name,
          "fps": (model.fps(for: device) * 10).rounded() / 10,
          "recording_seconds": Int(
            model.recordingStart(device).map { Date().timeIntervalSince($0) } ?? 0),
        ]
      }
      return json([
        "layout": model.layout.rawValue,
        "device": focusValue,
        "streams": streams,
      ])

    case "connect_device":
      let host = try required("host_port", arguments)
      let address = host.contains(":") ? host : "\(host):5555"
      let result = await AdbService.connect(hostPort: address)
      await model.refresh()
      // adb exits 0 even when the connection is refused, so read the message.
      let connected = result.combined.lowercased().contains("connected to")
      return json(["connected": connected, "address": address, "output": result.combined])

    case "pair_device":
      let host = try required("host_port", arguments)
      let code = try required("code", arguments)
      let result = await AdbService.pair(hostPort: host, code: code)
      if result.ok { await model.refreshMdns() }
      return json(["paired": result.ok, "output": result.combined])

    case "disconnect_device":
      let host = try required("host_port", arguments)
      let result = await AdbService.disconnect(hostPort: host)
      await model.refresh()
      return json(["disconnected": result.ok, "output": result.combined])

    case "install_app":
      let device = try findDevice(arguments, model: model)
      let path = try required("path", arguments)
      try await model.installApp(device, path: path)
      return json(["installed": path, "device": device.name])

    case "launch_app":
      let device = try findDevice(arguments, model: model)
      let app = try required("app", arguments)
      try await model.launchApp(
        device, app: app, clearState: arguments["clear_state"] as? Bool ?? false)
      return json(["launched": app, "device": device.name])

    case "record_device":
      let device = try findDevice(arguments, model: model)
      let url = await model.toggleRecording(device)
      if model.isRecording(device) { return json(["recording": device.name]) }
      if let url { return json(["saved": url.path]) }
      throw McpToolError.message(
        model.errorMessage ?? "Could not record \(device.name).")

    case "stop_device", "shutdown_device":
      let device = try findDevice(arguments, model: model)
      await model.stop(device)
      return json(["stopped": device.name])

    case "delete_device":
      let device = try findDevice(arguments, model: model)
      await model.delete(device)
      return json(["deleted": device.name])

    case "tap":
      let device = try findDevice(arguments, model: model)
      if let label = arguments["label"] as? String, !label.isEmpty {
        guard device.os == .android else {
          throw McpToolError.message(
            "Tapping by label supports Android devices only; pass x and y on iOS.")
        }
        guard let serial = device.serial else {
          throw McpToolError.message("Start \(device.name) first.")
        }
        let session = try await liveSession(arguments, model: model)
        let timeout = min(max(arguments["timeout_ms"] as? Int ?? 5000, 0), 60000)
        let index = arguments["index"] as? Int ?? 0
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        while true {
          let elements = await UiAutomation.elements(serial: serial)
          if let element = UiAutomation.locate(
            label: label, index: index, in: elements)
          {
            session.touch(.down, x: element.center.x, y: element.center.y)
            try? await Task.sleep(nanoseconds: 60_000_000)
            session.touch(.up, x: element.center.x, y: element.center.y)
            return json([
              "tapped": ["x": element.center.x, "y": element.center.y],
              "label": element.label,
            ])
          }
          if Date() >= deadline {
            throw McpToolError.message("No element matches \(label).")
          }
          try? await Task.sleep(nanoseconds: 400_000_000)
        }
      }
      guard arguments["x"] != nil, arguments["y"] != nil else {
        throw McpToolError.message("Pass x and y, or a label.")
      }
      let session = try await liveSession(arguments, model: model)
      let x = number(arguments["x"]), y = number(arguments["y"])
      session.touch(.down, x: x, y: y)
      session.touch(.up, x: x, y: y)
      return json(["tapped": ["x": x, "y": y]])

    case "find_elements":
      let device = try findDevice(arguments, model: model)
      guard device.os == .android, let serial = device.serial else {
        throw McpToolError.message(
          "find_elements supports Android devices only.")
      }
      let all = await UiAutomation.elements(serial: serial)
      let query = (arguments["label"] as? String ?? "")
        .trimmingCharacters(in: .whitespaces)
      let shown = all.filter { element in
        query.isEmpty
          ? !element.label.isEmpty || !element.value.isEmpty
          : UiElement.contains(element, query)
      }
      return json(["elements": shown.map(\.json)])

    case "swipe":
      let session = try await liveSession(arguments, model: model)
      let x1 = number(arguments["x1"]), y1 = number(arguments["y1"])
      let x2 = number(arguments["x2"]), y2 = number(arguments["y2"])
      let duration = min(max((arguments["duration_ms"] as? Int ?? 250), 50), 3000)
      let steps = 18
      session.touch(.down, x: x1, y: y1)
      for step in 1...steps {
        let t = Double(step) / Double(steps)
        session.touch(.move, x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
        try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000 / UInt64(steps))
      }
      session.touch(.up, x: x2, y: y2)
      return json(["swiped": ["x1": x1, "y1": y1, "x2": x2, "y2": y2]])

    case "type_text":
      let session = try await liveSession(arguments, model: model)
      let text = arguments["text"] as? String ?? ""
      session.typeText(text)
      return json(["typed": text])

    case "press_button":
      let session = try await liveSession(arguments, model: model)
      let raw = arguments["button"] as? String ?? "home"
      guard let button = DeviceButton(rawValue: raw) else {
        throw McpToolError.message("Unknown button \(raw).")
      }
      session.press(button)
      return json(["pressed": raw])

    case "screenshot":
      let device = try findDevice(arguments, model: model)
      let url = try await CaptureService.screenshot(device)
      return json(["path": url.path])

    default:
      throw McpToolError.message("Unknown tool \(name).")
    }
  }

  private func findDevice(_ arguments: [String: Any], model: AppModel) throws -> Device {
    let value = try required("device", arguments)
    guard
      let device = model.devices.first(where: {
        $0.key == value || $0.rawID == value || $0.name == value || $0.serial == value
      })
    else {
      throw McpToolError.message("No device matches \(value).")
    }
    return device
  }

  private func liveSession(
    _ arguments: [String: Any], model: AppModel
  ) async throws -> DeviceSession {
    let device = try findDevice(arguments, model: model)
    if model.session(for: device) == nil {
      await model.openStream(device)
    }
    guard let session = model.session(for: device) else {
      throw McpToolError.message(
        model.sessionErrors[device.key] ?? "The stream did not start.")
    }
    return session
  }

  private func selectedImage(
    _ arguments: [String: Any], model: AppModel
  ) throws -> SystemImage {
    if let package = arguments["image"] as? String,
      let image = model.images.first(where: { $0.packageId == package })
    {
      return image
    }
    let abi = arguments["abi"] as? String
    if let abi, let image = model.images.first(where: { $0.abi == abi }) {
      return image
    }
    let api = arguments["api"] as? Int
    if let api, let image = model.images.first(where: { $0.api == api }) {
      return image
    }
    guard let image = model.images.first else {
      throw McpToolError.message("No system image is installed.")
    }
    return image
  }

  private func required(_ key: String, _ arguments: [String: Any]) throws -> String {
    guard let value = arguments[key] as? String, !value.isEmpty else {
      throw McpToolError.message("Missing argument \(key).")
    }
    return value
  }

  private func number(_ value: Any?) -> Double {
    if let value = value as? Double { return min(max(value, 0), 1) }
    if let value = value as? Int { return min(max(Double(value), 0), 1) }
    if let value = value as? NSNumber { return min(max(value.doubleValue, 0), 1) }
    return 0.5
  }

  private func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: - Schemas

  private static let locationSchema: [String: Any] = [
    "type": "object",
    "properties": ["device": ["type": "string", "description": "Device id, name or adb serial"]],
    "required": ["device"],
  ]

  private static var tools: [[String: Any]] {
    func tool(
      _ name: String, _ description: String, properties: [String: Any] = [:],
      required: [String] = []
    ) -> [String: Any] {
      [
        "name": name,
        "description": description,
        "inputSchema": [
          "type": "object",
          "properties": properties,
          "required": required,
        ],
      ]
    }
    let string = ["type": "string"]
    let number = ["type": "number"]
    return [
      tool("list_devices", "List Android and iOS devices with their state."),
      tool("get_device_catalogs", "List installed system images and hardware profiles."),
      tool(
        "create_avd", "Create an Android emulator managed by SimDeck. Prefer this over running avdmanager or the emulator binary.",
        properties: [
          "name": ["type": "string", "description": "Display name; spaces are allowed and kept in avd.ini.displayname."],
          "image": ["type": "string", "description": "system-images;android-…;tag;abi"],
          "profile": ["type": "string"],
          "api": ["type": "integer"],
          "ram_mb": ["type": "integer"],
          "storage": string,
          "camera": string,
          "orientation": string,
          "keyboard": ["type": "boolean"],
        ], required: ["name"]),
      tool(
        "create_simulator", "Create an iOS simulator managed by SimDeck.",
        properties: ["name": string, "device_type": string, "runtime": string],
        required: ["name"]),
      tool(
        "start_device",
        "Boot a device headlessly inside SimDeck: no emulator window is opened and the screen appears in SimDeck. Use this instead of running the emulator binary. headless defaults to true; stream:false boots without opening a tile.",
        properties: [
          "device": string,
          "headless": ["type": "boolean", "default": true],
          "stream": ["type": "boolean", "default": true],
          "cold_boot": ["type": "boolean"],
        ], required: ["device"]),
      tool(
        "stream_device",
        "Open a running device's screen inside SimDeck before tapping or taking screenshots.",
        properties: ["device": string], required: ["device"]),
      tool("stop_device", "Shut a device down.", properties: ["device": string], required: ["device"]),
      tool("shutdown_device", "Shut a device down.", properties: ["device": string], required: ["device"]),
      tool("delete_device", "Delete an emulator or simulator.", properties: ["device": string], required: ["device"]),
      tool(
        "tap",
        "Tap at x,y normalized to 0..1, or on the element whose label, id or value matches label (exact, else contains; case-insensitive), waiting up to timeout_ms for it. Labels come from find_elements and work across screen sizes.",
        properties: [
          "device": string, "x": number, "y": number, "label": string,
          "timeout_ms": ["type": "integer", "default": 5000],
          "index": [
            "type": "integer", "default": 0,
            "description": "Which match when several share the label, in screen order; -1 is the last",
          ],
        ],
        required: ["device"]),
      tool(
        "find_elements",
        "Elements on screen from the Android accessibility tree: label, id, value, role, center x/y and frame [left, top, right, bottom], all normalized 0..1. Pass label to keep only matching ones; unfiltered, id-only containers are left out. Use these labels with tap {label}.",
        properties: ["device": string, "label": string],
        required: ["device"]),
      tool(
        "swipe", "Swipe between normalized coordinates.",
        properties: [
          "device": string, "x1": number, "y1": number, "x2": number, "y2": number,
          "duration_ms": ["type": "integer"],
        ],
        required: ["device", "x1", "y1", "x2", "y2"]),
      tool(
        "type_text", "Type text on the device.",
        properties: ["device": string, "text": string], required: ["device", "text"]),
      tool(
        "press_button", "Press back, home, recents, lock or a volume button.",
        properties: ["device": string, "button": string], required: ["device", "button"]),
      tool("screenshot", "Take a device screenshot and return its path.", properties: ["device": string], required: ["device"]),
      tool(
        "record_device",
        "Toggle recording a running device. Returns the saved file when stopping.",
        properties: ["device": string], required: ["device"]),
      tool(
        "record_grid",
        "Toggle recording the whole SimDeck grid (all tiles) to an MP4; grid and device recordings do not run together. quality: low (15 fps, 720p), standard (24 fps, 1280 px), high (30 fps, full size) or smooth (60 fps, full size); defaults to the app's setting.",
        properties: [
          "quality": [
            "type": "string",
            "enum": GridRecordQuality.allCases.map(\.rawValue),
          ]
        ]),
      tool(
        "get_spotlight",
        "The stream layout, the device shown large in the spotlight (null in the grid layout or with no streams) and each open stream with its fps and how long it has been recording."),
      tool(
        "connect_device",
        "Connect a wireless device; host_port is host:port or a bare host (port 5555).",
        properties: ["host_port": string], required: ["host_port"]),
      tool(
        "pair_device",
        "Pair a device with wireless debugging using its mDNS host:port and the pairing code.",
        properties: ["host_port": string, "code": string],
        required: ["host_port", "code"]),
      tool(
        "disconnect_device",
        "Disconnect a wireless device.",
        properties: ["host_port": string], required: ["host_port"]),
      tool(
        "install_app",
        "Install an app from this computer, replacing an installed copy: an .apk on Android or a simulator .app on iOS.",
        properties: [
          "device": string,
          "path": ["type": "string", "description": "Absolute path to the .apk or .app"],
        ], required: ["device", "path"]),
      tool(
        "launch_app",
        "Launch an app by Android package name or iOS simulator bundle id. clear_state also wipes its data (Android only).",
        properties: [
          "device": string,
          "app": string,
          "clear_state": ["type": "boolean", "default": false],
        ], required: ["device", "app"]),
    ]
  }
}

enum McpToolError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

private struct HttpRequest {
  let method: String
  let path: String
  let body: Data

  static func parse(_ data: Data) -> HttpRequest? {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
    let lines = head.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else { return nil }
    var length = 0
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let key = String(line[..<colon]).lowercased()
      if key == "content-length" {
        length = Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)) ?? 0
      }
    }
    let start = separator.upperBound
    guard data.count - start >= length else { return nil }
    return HttpRequest(
      method: String(parts[0]),
      path: String(parts[1]),
      body: data.subdata(in: start..<(start + length)))
  }
}

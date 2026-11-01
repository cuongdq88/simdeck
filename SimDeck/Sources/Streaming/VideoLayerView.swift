import SwiftUI

/// Hosts a session's display layer; SwiftUI only sizes and clips it.
struct VideoLayerView: NSViewRepresentable {
  let sink: VideoSink

  func makeNSView(context: Context) -> VideoHostView {
    VideoHostView(sink: sink)
  }

  func updateNSView(_ nsView: VideoHostView, context: Context) {
    // A tile can be reused for another device (the grid is built from
    // positions); swap the display layer so an iPhone never shows the last
    // Android frame.
    nsView.update(sink: sink)
  }
}

final class VideoHostView: NSView {
  private(set) var sink: VideoSink

  init(sink: VideoSink) {
    self.sink = sink
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    layer?.addSublayer(sink.layer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(sink: VideoSink) {
    guard sink !== self.sink else { return }
    self.sink.layer.removeFromSuperlayer()
    self.sink = sink
    layer?.addSublayer(sink.layer)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    sink.layer.frame = bounds
    CATransaction.commit()
  }
}

import CoreGraphics
import Foundation

/// One live stream of one device.
protocol DeviceSession: AnyObject {
  var deviceKey: String { get }
  var sink: VideoSink { get }
  var size: CGSize { get }
  var status: SessionStatus { get }
  var framesShown: Int { get }
  var onStatusChange: ((SessionStatus) -> Void)? { get set }

  func start() async throws
  func stop()
  func touch(_ phase: TouchPhase, x: Double, y: Double)
  func press(_ button: DeviceButton)
  func typeText(_ text: String)
  func rotate()
}

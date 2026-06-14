import AppKit
import AVFoundation
import QuartzCore

/// Common interface for everything that can fill a wallpaper window or
/// screensaver view. Implementations vend a ready-to-mount `NSView` and respond
/// to lifecycle calls so the power policy can pause work when nothing is visible.
///
/// All methods are expected to be called on the main thread.
public protocol WallpaperRenderer: AnyObject {
    var view: NSView { get }
    func start()
    func pause()
    func resume()
    func stop()
}

extension Scaling {
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit, .center: return .resizeAspect
        case .stretch: return .resize
        }
    }

    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        case .center: return .center
        }
    }
}

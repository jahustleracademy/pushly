import Foundation

#if os(iOS)
import AVFoundation
import CoreGraphics
import UIKit

struct PoseROIMetadata {
  let bufferSize: CGSize
  let orientation: CGImagePropertyOrientation
  let mirrored: Bool
  let roi: CGRect?
  let roiSource: ReacquireSource

  var summary: String {
    let roiText: String
    if let roi {
      roiText = String(format: "%.2f,%.2f %.2fx%.2f", roi.origin.x, roi.origin.y, roi.size.width, roi.size.height)
    } else {
      roiText = "full"
    }
    return "buf:\(Int(bufferSize.width))x\(Int(bufferSize.height)) ori:\(orientation.rawValue) mir:\(mirrored ? 1 : 0) roi:\(roiText) src:\(roiSource.rawValue)"
  }
}

enum PoseCoordinateConverter {
  struct ProjectionContext {
    let previewBounds: CGRect
    let pixelBufferSize: CGSize
    let videoGravity: AVLayerVideoGravity
    let orientation: CGImagePropertyOrientation
    let isMirrored: Bool

    init(
      previewBounds: CGRect,
      pixelBufferSize: CGSize,
      videoGravity: AVLayerVideoGravity,
      orientation: CGImagePropertyOrientation = .up,
      isMirrored: Bool = false
    ) {
      self.previewBounds = previewBounds
      self.pixelBufferSize = pixelBufferSize
      self.videoGravity = videoGravity
      self.orientation = orientation
      self.isMirrored = isMirrored
    }
  }

  static func previewRectToPixelBufferRect(
    previewRect: CGRect,
    previewBounds: CGRect,
    pixelBufferSize: CGSize,
    videoGravity: AVLayerVideoGravity,
    mirrored: Bool
  ) -> CGRect {
    guard previewBounds.width > 0,
          previewBounds.height > 0,
          pixelBufferSize.width > 0,
          pixelBufferSize.height > 0 else {
      return .zero
    }

    let normalizedPreview = CGRect(
      x: previewRect.minX / previewBounds.width,
      y: previewRect.minY / previewBounds.height,
      width: previewRect.width / previewBounds.width,
      height: previewRect.height / previewBounds.height
    )

    let contentRect = contentRectFor(
      previewBounds: previewBounds,
      pixelBufferSize: pixelBufferSize,
      videoGravity: videoGravity
    )

    let mapped = CGRect(
      x: (normalizedPreview.minX * previewBounds.width - contentRect.minX) / contentRect.width,
      y: (normalizedPreview.minY * previewBounds.height - contentRect.minY) / contentRect.height,
      width: (normalizedPreview.width * previewBounds.width) / contentRect.width,
      height: (normalizedPreview.height * previewBounds.height) / contentRect.height
    )

    let clamped = clampNormalizedROI(mapped)
    let normalizedForBuffer = mirrored ? mirrorNormalizedROI(clamped) : clamped

    return CGRect(
      x: normalizedForBuffer.minX * pixelBufferSize.width,
      y: normalizedForBuffer.minY * pixelBufferSize.height,
      width: normalizedForBuffer.width * pixelBufferSize.width,
      height: normalizedForBuffer.height * pixelBufferSize.height
    )
  }

  static func pixelBufferRectToVisionROI(
    pixelBufferRect: CGRect,
    pixelBufferSize: CGSize,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool
  ) -> CGRect {
    guard pixelBufferSize.width > 0, pixelBufferSize.height > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    var normalized = CGRect(
      x: pixelBufferRect.minX / pixelBufferSize.width,
      y: pixelBufferRect.minY / pixelBufferSize.height,
      width: pixelBufferRect.width / pixelBufferSize.width,
      height: pixelBufferRect.height / pixelBufferSize.height
    )

    normalized = clampNormalizedROI(normalized)
    if mirrored {
      normalized = mirrorNormalizedROI(normalized)
    }

    return orientToVision(normalized, orientation: orientation)
  }

  static func canonicalPointFromMediaPipe(
    _ point: CGPoint,
    mirrored: Bool
  ) -> CGPoint {
    // MediaPipe normalized coordinates are top-left origin. Canonical pose space in this
    // app uses bottom-left origin to match Vision.
    var normalized = CGPoint(x: point.x, y: 1 - point.y)
    if mirrored {
      normalized.x = 1 - normalized.x
    }
    return clampNormalizedPoint(normalized)
  }

  static func pointFromCanonical(
    _ point: CGPoint,
    projection: ProjectionContext
  ) -> CGPoint {
    var normalized = clampNormalizedPoint(point)
    if projection.isMirrored {
      normalized.x = 1 - normalized.x
    }

    let orientedBuffer = orientedPixelBufferSize(
      projection.pixelBufferSize,
      orientation: projection.orientation
    )
    let contentRect = contentRectFor(
      previewBounds: projection.previewBounds,
      pixelBufferSize: orientedBuffer,
      videoGravity: projection.videoGravity
    )

    // Canonical is bottom-left origin; preview layer space is top-left.
    let topLeft = CGPoint(x: normalized.x, y: 1 - normalized.y)
    return CGPoint(
      x: contentRect.minX + topLeft.x * contentRect.width,
      y: contentRect.minY + topLeft.y * contentRect.height
    )
  }

  static func previewPointFromCanonical(
    _ point: CGPoint,
    projection: ProjectionContext
  ) -> CGPoint {
    pointFromCanonical(point, projection: projection)
  }

  static func visionROIFromCanonical(
    _ canonicalROI: CGRect,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool
  ) -> CGRect {
    var normalized = clampNormalizedROI(canonicalROI)
    if mirrored {
      normalized = mirrorNormalizedROI(normalized)
    }
    return orientToVision(normalized, orientation: orientation)
  }

  static func clampNormalizedROI(_ roi: CGRect, minSize: CGFloat = 0.05) -> CGRect {
    let clampedMinX = min(1, max(0, roi.minX))
    let clampedMinY = min(1, max(0, roi.minY))
    let clampedMaxX = min(1, max(0, roi.maxX))
    let clampedMaxY = min(1, max(0, roi.maxY))

    var width = max(minSize, clampedMaxX - clampedMinX)
    var height = max(minSize, clampedMaxY - clampedMinY)

    if clampedMinX + width > 1 { width = 1 - clampedMinX }
    if clampedMinY + height > 1 { height = 1 - clampedMinY }

    return CGRect(x: clampedMinX, y: clampedMinY, width: max(minSize, width), height: max(minSize, height))
  }

  static func orientToVision(_ roi: CGRect, orientation: CGImagePropertyOrientation) -> CGRect {
    switch orientation {
    case .up:
      return roi
    case .upMirrored:
      return mirrorNormalizedROI(roi)
    case .down:
      return CGRect(x: 1 - roi.maxX, y: 1 - roi.maxY, width: roi.width, height: roi.height)
    case .downMirrored:
      return CGRect(x: roi.minX, y: 1 - roi.maxY, width: roi.width, height: roi.height)
    case .left:
      return CGRect(x: roi.minY, y: 1 - roi.maxX, width: roi.height, height: roi.width)
    case .leftMirrored:
      return CGRect(x: 1 - roi.maxY, y: 1 - roi.maxX, width: roi.height, height: roi.width)
    case .right:
      return CGRect(x: 1 - roi.maxY, y: roi.minX, width: roi.height, height: roi.width)
    case .rightMirrored:
      return CGRect(x: roi.minY, y: roi.minX, width: roi.height, height: roi.width)
    @unknown default:
      return roi
    }
  }

  static func uiOrientation(from orientation: CGImagePropertyOrientation, allowMirrored: Bool) -> UIImage.Orientation {
    switch orientation {
    case .up:
      return .up
    case .upMirrored:
      return allowMirrored ? .upMirrored : .up
    case .down:
      return .down
    case .downMirrored:
      return allowMirrored ? .downMirrored : .down
    case .left:
      return .left
    case .leftMirrored:
      return allowMirrored ? .leftMirrored : .left
    case .right:
      return .right
    case .rightMirrored:
      return allowMirrored ? .rightMirrored : .right
    @unknown default:
      return .up
    }
  }

  static func mirrorNormalizedROI(_ roi: CGRect) -> CGRect {
    CGRect(x: 1 - roi.maxX, y: roi.minY, width: roi.width, height: roi.height)
  }

  static func clampNormalizedPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
  }

  private static func contentRectFor(
    previewBounds: CGRect,
    pixelBufferSize: CGSize,
    videoGravity: AVLayerVideoGravity
  ) -> CGRect {
    if videoGravity == .resize {
      return previewBounds
    }

    let previewW = max(0.001, previewBounds.width)
    let previewH = max(0.001, previewBounds.height)
    let bufferW = max(0.001, pixelBufferSize.width)
    let bufferH = max(0.001, pixelBufferSize.height)

    let scale: CGFloat
    if videoGravity == .resizeAspectFill {
      scale = max(previewW / bufferW, previewH / bufferH)
    } else {
      // .resizeAspect (fit)
      scale = min(previewW / bufferW, previewH / bufferH)
    }

    let scaledW = bufferW * scale
    let scaledH = bufferH * scale
    let x = previewBounds.minX + (previewW - scaledW) * 0.5
    let y = previewBounds.minY + (previewH - scaledH) * 0.5
    return CGRect(x: x, y: y, width: scaledW, height: scaledH)
  }

  private static func orientedPixelBufferSize(
    _ size: CGSize,
    orientation: CGImagePropertyOrientation
  ) -> CGSize {
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      return CGSize(width: size.height, height: size.width)
    default:
      return size
    }
  }
}
#endif

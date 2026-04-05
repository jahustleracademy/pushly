import Foundation

#if os(iOS)
import AVFoundation
import Vision

final class ReacquireDetector {
  private let config: PushlyPoseConfig
  private let sequenceHandler = VNSequenceRequestHandler()
  private let faceRequest = VNDetectFaceRectanglesRequest()
  private let humanRequest = VNDetectHumanRectanglesRequest()

  init(config: PushlyPoseConfig) {
    self.config = config
    humanRequest.upperBodyOnly = true
  }

  func detect(
    sampleBuffer: CMSampleBuffer,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool
  ) -> ReacquireObservation? {
    if config.reacquire.enableFaceDetector,
       let face = detectFace(sampleBuffer: sampleBuffer, orientation: orientation, mirrored: mirrored) {
      return ReacquireObservation(source: .face, roi: face)
    }

    if config.reacquire.enableUpperBodyDetector,
       let upperBody = detectUpperBody(sampleBuffer: sampleBuffer, orientation: orientation, mirrored: mirrored) {
      return ReacquireObservation(source: .upperBody, roi: upperBody)
    }

    return nil
  }

  private func detectFace(
    sampleBuffer: CMSampleBuffer,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool
  ) -> CGRect? {
    do {
      try sequenceHandler.perform([faceRequest], on: sampleBuffer, orientation: orientation)
      guard let rect = faceRequest.results?.first?.boundingBox else { return nil }
      let expanded = expandFaceRect(rect)
      return normalizeCandidate(expanded, mirrored: mirrored)
    } catch {
      return nil
    }
  }

  private func detectUpperBody(
    sampleBuffer: CMSampleBuffer,
    orientation: CGImagePropertyOrientation,
    mirrored: Bool
  ) -> CGRect? {
    do {
      try sequenceHandler.perform([humanRequest], on: sampleBuffer, orientation: orientation)
      guard let rect = humanRequest.results?.first?.boundingBox else { return nil }
      let expanded = expandUpperBodyRect(rect)
      return normalizeCandidate(expanded, mirrored: mirrored)
    } catch {
      return nil
    }
  }

  private func expandFaceRect(_ rect: CGRect) -> CGRect {
    let width = max(0.18, rect.width * (1 + config.reacquire.facePaddingX * 2))
    let height = max(0.3, rect.height * (1 + config.reacquire.facePaddingY * 2))
    let midX = rect.midX
    let midY = rect.midY - rect.height * 0.2
    return CGRect(x: midX - width * 0.5, y: midY - height * 0.5, width: width, height: height)
  }

  private func expandUpperBodyRect(_ rect: CGRect) -> CGRect {
    let width = max(0.2, rect.width * (1 + config.reacquire.upperBodyPaddingX * 2))
    let height = max(0.28, rect.height * (1 + config.reacquire.upperBodyPaddingY * 2))
    let midX = rect.midX
    let midY = rect.midY - rect.height * 0.08
    return CGRect(x: midX - width * 0.5, y: midY - height * 0.5, width: width, height: height)
  }

  private func normalizeCandidate(_ rect: CGRect, mirrored: Bool) -> CGRect {
    let mirroredRect = mirrored
      ? CGRect(x: 1 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
      : rect
    return PoseCoordinateConverter.clampNormalizedROI(mirroredRect, minSize: config.reacquire.roiMinSize)
  }
}
#endif

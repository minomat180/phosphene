import CoreMedia
import CoreVideo
import Foundation

/// Wrap `image` in an IOSurface-backed `CMSampleBuffer` at PTS zero, sized to the
/// image. Returns nil if any Core Video/Media step fails.
///
/// `taggedSRGB` converts the image to sRGB and tags the buffer as sRGB. Untagged, the
/// display layer takes the pixels as display-native, which oversaturates and darkens a
/// photo on a wide-gamut panel.
func makeStillSampleBuffer(from image: CGImage, taggedSRGB: Bool = false) -> CMSampleBuffer? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let pixelBufferAttributes: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]

    var pixelBufferOut: CVPixelBuffer?
    guard CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        pixelBufferAttributes as CFDictionary, &pixelBufferOut,
    ) == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

    let colorSpace = taggedSRGB ? CGColorSpace(name: CGColorSpace.sRGB)! : CGColorSpaceCreateDeviceRGB()
    if taggedSRGB {
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription,
    ) == noErr, let format = formatDescription else { return nil }

    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
        formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sampleBuffer,
    ) == noErr else { return nil }

    return sampleBuffer
}

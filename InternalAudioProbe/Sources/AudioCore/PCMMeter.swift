import AVFoundation
import CoreMedia

/// Reads the buffer's declared PCM format, including non-native byte order.
/// Metering never changes the samples submitted to the AAC encoder.
public enum PCMMeter {
    public static func peak(of sample: CMSampleBuffer) -> Double? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM else { return nil }
        let channels = max(1, Int(format.mChannelsPerFrame))
        let list = AudioBufferList.allocate(maximumBuffers: channels)
        defer { list.unsafeMutablePointer.deallocate() }
        var retained: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample, bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer,
            bufferListSize: MemoryLayout<AudioBufferList>.size + (channels - 1) * MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retained
        )
        guard status == noErr else { return nil }
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let big = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        let bits = Int(format.mBitsPerChannel)
        guard (floating && (bits == 32 || bits == 64)) || (signed && (bits == 16 || bits == 32)) else { return nil }
        var maximum: Double = 0
        for buffer in list {
            guard let data = buffer.mData else { continue }
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            let stride = bits / 8
            for offset in Swift.stride(from: 0, to: Int(buffer.mDataByteSize) - stride + 1, by: stride) {
                var word: UInt64 = 0
                for index in 0..<stride {
                    let shift = big ? (stride - index - 1) * 8 : index * 8
                    word |= UInt64(bytes[offset + index]) << shift
                }
                let value: Double
                if floating && bits == 32 { value = Double(Float(bitPattern: UInt32(word))) }
                else if floating { value = Double(bitPattern: word) }
                else if bits == 16 { value = Double(Int16(bitPattern: UInt16(word))) / 32768 }
                else { value = Double(Int32(bitPattern: UInt32(word))) / 2147483648 }
                if value.isFinite { maximum = max(maximum, abs(value)) }
            }
        }
        return maximum
    }
}

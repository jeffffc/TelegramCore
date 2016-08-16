import Foundation
import Darwin
import TelegramCorePrivate

public final class RingByteBuffer {
    public let size: Int
    private var buffer: TPCircularBuffer
    
    public init(size: Int) {
        self.size = size
        self.buffer = TPCircularBuffer()
        TPCircularBufferInit(&self.buffer, Int32(size))
        TPCircularBufferSetAtomic(&self.buffer, false)
    }
    
    deinit {
        TPCircularBufferCleanup(&self.buffer)
    }
    
    public func enqueue(data: Data) -> Bool {
        return data.withUnsafeBytes { (bytes: UnsafePointer<Void>) -> Bool in
            return TPCircularBufferProduceBytes(&self.buffer, bytes, Int32(data.count))
        }
    }
    
    public func enqueue(_ bytes: UnsafePointer<Void>, count: Int) -> Bool {
        return TPCircularBufferProduceBytes(&self.buffer, bytes, Int32(count))
    }
    
    public func withMutableHeadBytes(_ f: @noescape(UnsafeMutablePointer<Void>, Int) -> Int) {
        var availableBytes: Int32 = 0
        let bytes = TPCircularBufferHead(&self.buffer, &availableBytes)
        let enqueuedBytes = f(bytes!, Int(availableBytes))
        TPCircularBufferProduce(&self.buffer, Int32(enqueuedBytes))
    }
    
    public func dequeue(_ bytes: UnsafeMutablePointer<Void>, count: Int) -> Int {
        var availableBytes: Int32 = 0
        let tail = TPCircularBufferTail(&self.buffer, &availableBytes)
        
        let copiedCount = min(count, Int(availableBytes))
        memcpy(bytes, tail, copiedCount)
        
        TPCircularBufferConsume(&self.buffer, Int32(copiedCount))
        
        return copiedCount
    }
    
    public func dequeue(count: Int) -> Data {
        var availableBytes: Int32 = 0
        let tail = TPCircularBufferTail(&self.buffer, &availableBytes)
        
        let copiedCount = min(count, Int(availableBytes))
        let bytes = malloc(copiedCount)!
        memcpy(bytes, tail, copiedCount)
        
        TPCircularBufferConsume(&self.buffer, Int32(copiedCount))
        
        return Data(bytesNoCopy: UnsafeMutablePointer<UInt8>(bytes), count: copiedCount, deallocator: .free)
    }
    
    public func clear() {
        TPCircularBufferClear(&self.buffer)
    }
    
    public var availableBytes: Int {
        var count: Int32 = 0
        TPCircularBufferTail(&self.buffer, &count)
        return Int(count)
    }
}
//
//  DataDecompressionExtension.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/13.
//

import Foundation
import Cocoa
import Compression


// MARK: - Typealias -
/**
 작업 Config Typealias
 - Parameters:
    - operation: `compression_stream_operation`
    - algorithm: `compression_algorithm`
 */
fileprivate typealias Config = (operation: compression_stream_operation, algorithm: compression_algorithm)

// MARK: - Extension for Decompression -
extension Data {
    
    /// [libcompression documentation](https://developer.apple.com/reference/compression/1665429-data_compression) 참고
    /// zlib  : ZIP 파일 압축 해제에 사용. 현재는 이것만 사용한다
    /// lzfse : Apples custom Lempel-Ziv style compression algorithm. Claims to compress as good as zlib but 2 to 3 times faster.
    /// lzma  : Horribly slow. Compression as well as decompression. Compresses better than zlib though.
    /// lz4   : Fast, but compression rate is very bad. Apples lz4 implementation often to not compress at all.
    enum CompressionAlgorithm {
        case zlib
        case lzfse
        case lzma
        case lz4
    }

    /// CRC32 계산값 반환
    internal func crc32() -> UInt {
        return UInt(self.checkCrc32().checksum)
    }
    
    /// CRC32 구조체 생성, 반환
    /// - returns: CRC32 구조체 반환
    private func checkCrc32() -> CRC32 {
        var checkCrc32 = CRC32()
        checkCrc32.advance(withChunk: self)
        return checkCrc32
    }
    
    /**
     ZIP 파일 압축 해제
     - Parameters:
        - offset: 건너뛰어야 할 헤더 부분 offset 값을 지정
        - compressedSize: 압축되어 있는 크기
        - crc32: `UInt`로 CRC 값 지정. CRC32 체크시 해당 값을 입력. nil로 지정하는 경우, CRC 체크를 건너뛴다
     - Returns: 압축 해제된 Data 반환. 실패시 에러값 반환
     */
    internal func unzip(offset: Int, compressedSize: Int, crc32: UInt?) throws -> Data {
        let result: Data? = try self.withUnsafeBytes { (bytes) -> Data? in
            let source = bytes.baseAddress?.advanced(by: offset)
            guard let sourcePointer = source?.bindMemory(to: UInt8.self, capacity: compressedSize) else {
                // 미확인 에러를 반환한다
                throw StreamZip.Error.unknown
            }
            
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
            return performDecompress(config, source: sourcePointer, sourceSize: compressedSize)
        }
        guard let deflated = result else {
            print("StreamZip>DataDecompressionExtension>unzip(): 해제 실패")
            // 해제 실패 에러를 반환한다
            throw StreamZip.Error.deflationIsFailed
        }

        // crc32 값이 입력된 경우, 체크섬 확인 진행
        if let inputCrc32 = crc32 {
            let outputCrc32 = deflated.crc32()
            guard inputCrc32 == outputCrc32 else {
                print("StreamZip>DataDecompressionExtension>unzip(): 원본 CRC = \(inputCrc32) || 계산값 = \(outputCrc32) 이 일치하지 않는다")
                // checksum 불일치 에러를 반환한다
                throw StreamZip.Error.checksumIsDifferent
            }
        }
        
        // 값이 입력되지 않은 경우 또는 crc 체크섬 확인에 통과한 경우
        return deflated
    }
}

// MARK: Function
/**
 압축 해제 실행 Function
 - Parameters:
    - config: `Config` 타입으로 compression_stream_operation, compression_algorithm 지정
    - source: 데이터 중 압축 해제게 필요한 부분을 `UnsafePointer<UInt8>`로 전달
    - sourceSize: 압축된 소스 크기
    - preload: 현재 사용하지 않음
 - Returns: 압축 해제된 `Data` 반환. 실패시 nil 반환
 */
fileprivate func performDecompress(_ config: Config, source: UnsafePointer<UInt8>, sourceSize: Int, preload: Data = Data()) -> Data? {
    guard config.operation == COMPRESSION_STREAM_ENCODE || sourceSize > 0 else { return nil }
    
    let streamBase = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { streamBase.deallocate() }
    var stream = streamBase.pointee
    
    let status = compression_stream_init(&stream, config.operation, config.algorithm)
    guard status != COMPRESSION_STATUS_ERROR else { return nil }
    defer { compression_stream_destroy(&stream) }

    var result = preload
    var flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
    let blockLimit = 64 * 1024
    var bufferSize = Swift.max(sourceSize, 64)

    if sourceSize > blockLimit {
        bufferSize = blockLimit
        if config.algorithm == COMPRESSION_LZFSE && config.operation != COMPRESSION_STREAM_ENCODE   {
            // This fixes a bug in Apples lzfse decompressor. it will sometimes fail randomly when the input gets
            // splitted into multiple chunks and the flag is not 0. Even though it should always work with FINALIZE...
            flags = 0
        }
    }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    stream.dst_ptr  = buffer
    stream.dst_size = bufferSize
    stream.src_ptr  = source
    stream.src_size = sourceSize
    
    while true {
        switch compression_stream_process(&stream, flags) {
            case COMPRESSION_STATUS_OK:
                guard stream.dst_size == 0 else { return nil }
                result.append(buffer, count: stream.dst_ptr - buffer)
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize

                // part of the lzfse bugfix above
                if flags == 0 && stream.src_size == 0 {
                    flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                }
                
            case COMPRESSION_STATUS_END:
                result.append(buffer, count: stream.dst_ptr - buffer)
                return result
                
            default:
                return nil
        }
    }
}

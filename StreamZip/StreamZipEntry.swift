//
//  StreamZipEntry.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

// MARK: - Stream Zip Enumerations -

/// StreamZip 열거형
enum StreamZip {
    
    /// 에러
    enum Error: LocalizedError {
        /// 반응이 없는 경우
        case responseIsEmpty
        /// 컨텐츠가 없는 경우
        case contentsIsEmpty
        /// 알 수 없는 에러
        case unknown
        
        /**
         Error Description
         */
        public var errorDescription: String? {
            switch self {
            case .responseIsEmpty: return "No reponse"
            case .contentsIsEmpty: return "Contents is empty"
            default: return "Unknown error was occurred"
            }
        }
    }
}

// MARK: - Stream Zip Static Properties -

/// 에러 도메인
let StreamZipEntryErrorDoman = "streamzip.entry.error"

/// Central Directory 마지막 부분 signature
let EndOfCentralDirectorySignature: Array<CChar> = [0x50, 0x4b, 0x05, 0x06]


// MARK: - Stream Zip Entry Class -
/**
 StreamZipEntry 클래스
 */
class StreamZipEntry: Codable {
    
    // MARK: - Properties
    /// URL
    var url: URL
    /// 하위 경로
    var filePath: String
    /// offset
    var offset: Int
    /// method
    var method: Int
    /// 압축 크기
    var sizeCompressed: Int
    /// 비압축 크기
    var sizeUncompressed: Int
    /// crc32
    var crc32: UInt
    /// 파일명 길이
    var filenameLength: Int
    /// 부가 필드 길이
    var extraFieldLength: Int
    
    /// 데이터
    var data: Data?
    
    // MARK: - Initialization
    /// 기본 초기화
    init(_ url: URL,
         filePath: String,
         offset: Int,
         method: Int,
         sizeCompressed: Int,
         sizeUncompressed: Int,
         crc32: UInt,
         filenameLength: Int,
         extraFieldLength: Int,
         data: Data?) {
        self.url = url
        self.filePath = filePath
        self.offset = offset
        self.method = method
        self.sizeCompressed = sizeCompressed
        self.sizeUncompressed = sizeUncompressed
        self.crc32 = crc32
        self.filenameLength = filenameLength
        self.extraFieldLength = extraFieldLength
        self.data = data
    }
    /// 초기화(data 제외)
    convenience init(_ url: URL,
                     filePath: String,
                     offset: Int,
                     method: Int,
                     sizeCompressed: Int,
                     sizeUncompressed: Int,
                     crc32: UInt,
                     filenameLength: Int,
                     extraFieldLength: Int) {
        self.init(url,
                  filePath:filePath,
                  offset:offset,
                  method: method,
                  sizeCompressed: sizeCompressed,
                  sizeUncompressed: sizeUncompressed,
                  crc32: crc32,
                  filenameLength: filenameLength,
                  extraFieldLength: extraFieldLength,
                  data: nil)
    }
    
    // MARK: - Encoding and Decoding
}

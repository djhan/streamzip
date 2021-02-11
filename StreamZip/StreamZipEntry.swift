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

/// End of Central Directory signature
let EndOfCentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x05, 0x06]
/// 개별 Central Directory signature
let CentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x01, 0x02]


// MARK: - Stream Zip Entry Class -
/**
 StreamZipEntry 클래스
 */
class StreamZipEntry: Codable {
    
    // MARK: - Properties
    /// 상위 URL
    var url: URL
    /// 파일 경로 (파일명)
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
    /// 최종 수정날짜
    var modificationDate: Date
    
    /// extraField
    var extraField: String?
    /// comment
    var comment: String?
    
    /// 데이터
    var data: Data?
    
    // MARK: - Static Methods
    
    static func makeEntries(_ url: URL, from data: Data, encoding: String.Encoding) -> [StreamZipEntry]? {
        var offset = 0
        var entries: [StreamZipEntry]?
        
        repeat {
            // 최초 4바이트가 CentralDirectorySignature에 해당되는지 확인. 아닌 경우 nil 반환
            var signature = [UInt8].init(repeating: 0, count: 4)
            data[offset ..< offset + 4].copyBytes(to: &signature, count: 4)
            guard signature == CentralDirectorySignature else { break }

            // centralDirectoryFileHeaderSignature 만큼 offset 이동
            offset += sizeof(UInt32.self)
            // versionMadeBy / versionNeededToExtract / generalPurposeBitFlag 만큼 offset 이동
            offset += sizeof(UInt16.self) * 3
            guard let compressionMethod: UInt16 = getValue(from: data, offset: &offset) else { break }
            guard let fileLastModificationTime: UInt16 = getValue(from: data, offset: &offset) else { break }
            guard let fileLastModificationDate: UInt16 = getValue(from: data, offset: &offset) else { break }
            guard let crc32: UInt32 = getValue(from: data, offset: &offset) else { break }
            guard let compressedSize: UInt32 = getValue(from: data, offset: &offset) else { break }
            guard let uncompressedSize: UInt32 = getValue(from: data, offset: &offset) else { break }
            guard let fileNameLength: UInt16 = getValue(from: data, offset: &offset) else { break }
            guard let extraFieldLength: UInt16 = getValue(from: data, offset: &offset) else { break }
            guard let fileCommentLength: UInt16 = getValue(from: data, offset: &offset) else { break }
            // diskNumberWhereFileStarts / internalFileAttributes / externalFileAttributes / relativeOffsetOfLocalFileHeader만큼 offset 이동
            offset += sizeof(UInt16.self) * 2
            offset += sizeof(UInt32.self) * 2
            guard let fileNameData = getData(from: data, offset: &offset, length: Int(fileNameLength)) else { break }

            // 파일명 생성
            guard let fileName = String.init(data: fileNameData, encoding: encoding) else { break }
            // 최종 수정일 생성
            guard let modificationDate = getDate(fromTime: fileLastModificationTime, fromDate: fileLastModificationDate) else { break }
            // extra field 생성
            var extraField: String?
            if let extraFieldData = getData(from: data, offset: &offset, length: Int(extraFieldLength)) {
                extraField = String.init(data: extraFieldData, encoding: encoding)
            }
            // comment 생성
            var fileComment: String?
            if let fileCommentData = getData(from: data, offset: &offset, length: Int(fileCommentLength)) {
                fileComment = String.init(data: fileCommentData, encoding: encoding)
            }

            let entry = StreamZipEntry.init(url,
                                            filePath: fileName,
                                            offset: offset,
                                            method: Int(compressionMethod),
                                            sizeCompressed: Int(compressedSize),
                                            sizeUncompressed: Int(uncompressedSize),
                                            crc32: UInt(crc32),
                                            modificationDate: modificationDate,
                                            extraField: extraField,
                                            comment: fileComment)
            if entries == nil { entries = [StreamZipEntry]() }
            entries?.append(entry)
        } while (offset < data.count)
        // records 배열을 반환
        return entries
    }
    
    // MARK: - Initialization
    /// 기본 초기화
    init(_ url: URL,
         filePath: String,
         offset: Int,
         method: Int,
         sizeCompressed: Int,
         sizeUncompressed: Int,
         crc32: UInt,
         modificationDate: Date,
         extraField: String?,
         comment: String?,
         data: Data?) {
        self.url = url
        self.filePath = filePath
        self.offset = offset
        self.method = method
        self.sizeCompressed = sizeCompressed
        self.sizeUncompressed = sizeUncompressed
        self.crc32 = crc32
        self.modificationDate = modificationDate
        self.extraField = extraField
        self.comment = comment
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
                     modificationDate: Date,
                     extraField: String?,
                     comment: String?) {
        self.init(url,
                  filePath:filePath,
                  offset:offset,
                  method: method,
                  sizeCompressed: sizeCompressed,
                  sizeUncompressed: sizeUncompressed,
                  crc32: crc32,
                  modificationDate: modificationDate,
                  extraField: extraField,
                  comment: comment,
                  data: nil)
    }
    
    // MARK: - Encoding and Decoding
}

//
//  StreamZipStructures.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

/// End of Central Directory signature
let EndOfCentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x05, 0x06]
/// 개별 Central Directory signature
let CentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x01, 0x02]
/// 개별 Local File Header signature
let LocalFileHeaderSignature: Array<UInt8> = [0x50, 0x4b, 0x03, 0x04]

// MARK: - Content of Directory Struct -
/// 디렉토리 하위 Content 구조체
/// - 파일 경로와 길이 등 최소한의 정보만 격납한다
internal struct ContentOfDirectory {
    /// 경로
    var path: String
    /// 디렉토리 여부
    var isDirectory: Bool
    /// 파일 크기
    var size: UInt
}

// MARK: - Zip Information Protocol -
internal protocol ZipInformationConvertible {
    /// 자기 자신의 길이
    var length: Int { get set }
    
    /**
     Data 기반으로 Zip 정보 구조체 생성후 반환
     - 인코딩은 utf-8을 사용
     - Parameters:
        - data: `Data`
     - Returns: 자기 자신의 struct를 반환. 실패시 nil 반환
     */
    static func make(from data: Data) -> Self?
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 생성후 반환
     - Parameters:
        - data: `Data`
        - encoding: `String.Encoding`. 미지정시 자동 인코딩
     - Returns: 자기 자신의 struct를 반환. 실패시 nil 반환
     */
    static func make(from data: Data, encoding: String.Encoding?) -> Self?

    /**
     data로부터 특정 프로퍼티 값 반환
     - offset를 inout 패러미터로 지정
     `FixedWidthInteger` 타입만 지정 가능
     - Parameters:
        - data: `Data`
        - offset: inout로 시작 지점 지정. 프로퍼티의 size를 추가해서 반환한다
     - Returns: `FixedWidthInteger` 타입 프로퍼티 반환. 실패시 nil 반환
     */
    @discardableResult
    static func getValue<T: FixedWidthInteger>(from data: Data, offset: inout Int) -> T?
    /**
     data로부터 데이터를 잘라내서 반환
     - offset를 inout 패러미터로 지정
     - Parameters:
        - data: `Data`
        - offset: inout로 시작 지점 지정. 성공시 가져온 length 만큼 추가된다
        - length: 특정 길이만큼 데이터를 가져온다
     - Returns: Data 반환. 실패시 nil 반환
     */
    @discardableResult
    static func getData(from data: Data, offset: inout Int, length: Int) -> Data?
}
extension ZipInformationConvertible {
    /**
     Data 기반으로 Zip 정보 구조체 생성후 반환
     - 인코딩은 utf-8을 사용
     - Parameters:
        - data: `Data`
     - Returns: 자기 자신의 struct를 반환. 실패시 nil 반환
     */
    static func make(from data: Data) -> Self? {
        return self.make(from: data, encoding: .utf8)
    }

    /**
     data로부터 데이터를 잘라내서 Generi으로 반환
     - offset를 inout 패러미터로 지정
     - Parameters:
        - data: `Data`
        - offset: inout로 시작 지점 지정. 성공시 가져온 length 만큼 추가된다
     - Returns: `FixedWidthInteger`형의 Generic으로 반환. 실패시 nil 반환
     */
    @discardableResult
    static func getValue<T: FixedWidthInteger>(from data: Data, offset: inout Int) -> T? {
        // 가져올 길이를 property의 타입 기준으로 구한다
        let length = T.bitWidth/UInt8.bitWidth
        guard offset + length <= data.count else { return nil }
        let property: T = data.getValue(from: offset, length: length, endian: .little)
        // offset에 length를 추가한다
        offset += length
        return property
    }
    /**
     data로부터 데이터를 잘라내서 Data로 반환
     - offset를 inout 패러미터로 지정
     - Parameters:
        - data: `Data`
        - offset: inout로 시작 지점 지정. 성공시 가져온 length 만큼 추가된다
        - length: 특정 길이만큼 데이터를 가져온다
     - Returns: Data 반환. 실패시 nil 반환
     */
    @discardableResult
    static func getData(from data: Data, offset: inout Int, length: Int) -> Data? {
        guard offset + length <= data.count else { return nil }
        let data = data[offset ..< offset + length]
        // offset에 length를 추가한다
        offset += length
        return data
    }
}

// MARK: - End of Central Directory Struct -
/// Zip End Record 구조체
internal struct ZipEndRecord: ZipInformationConvertible {
    
    var length: Int
    
    var endOfCentralDirectorySignature: UInt32
    var numberOfThisDisk: UInt16
    var diskWhereCentralDirectoryStarts: UInt16
    var numberOfCentralDirectoryRecordsOnThisDisk: UInt16
    var totalNumberOfCentralDirectoryRecords: UInt16
    var sizeOfCentralDirectory: UInt32
    var offsetOfStartOfCentralDirectory: UInt32
    var zipFileCommentLength: UInt16
    var comment: String?
    
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 생성후 반환
     */
    static func make(from data: Data, encoding: String.Encoding?) -> Self? {
        var offset = NSNotFound
        var signature = [UInt8].init(repeating: 0, count: 4)
        // 0번째부터 순환하며 end of central directory signature를 찾는다
        for index in 0 ..< data.count - 4  {
            data[index ..< index + 4].copyBytes(to: &signature, count: 4)
            if signature == EndOfCentralDirectorySignature {
                offset = index
                break
            }
        }
        // 미발견시 nil 반환
        guard offset != NSNotFound else { return nil }

        guard let endOfCentralDirectorySignature: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let numberOfThisDisk: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let diskWhereCentralDirectoryStarts: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let numberOfCentralDirectoryRecordsOnThisDisk: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let totalNumberOfCentralDirectoryRecords: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let sizeOfCentralDirectory: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let offsetOfStartOfCentralDirectory: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let zipFileCommentLength: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        var comment: String?
        if zipFileCommentLength > 0 {
            // commentData를 구한다
            let commentData = data[offset ..< offset + Int(zipFileCommentLength)]
            // 인코딩이 nil 인 경우, 자동 추정 실행
            if encoding == nil {
                comment = commentData.autoDetectEncodingString()
            }
            // encoding이 주어졌거나, 자동 인코딩 추정에 실패한 경우
            if comment == nil {
                let finalEncoding = encoding != nil ? encoding! : .utf8
                comment = String.init(data: commentData, encoding: finalEncoding)
            }
        }

        return Self.init(length: offset,
                         endOfCentralDirectorySignature: endOfCentralDirectorySignature,
                         numberOfThisDisk: numberOfThisDisk,
                         diskWhereCentralDirectoryStarts: diskWhereCentralDirectoryStarts,
                         numberOfCentralDirectoryRecordsOnThisDisk: numberOfCentralDirectoryRecordsOnThisDisk,
                         totalNumberOfCentralDirectoryRecords: totalNumberOfCentralDirectoryRecords,
                         sizeOfCentralDirectory: sizeOfCentralDirectory,
                         offsetOfStartOfCentralDirectory: offsetOfStartOfCentralDirectory,
                         zipFileCommentLength: zipFileCommentLength,
                         comment: comment)
    }
    
    /**
     Data 기반으로 Zip 정보 구조체 배열 생성후 반환
     - 미사용
     */
    static func makeRecords(from data: Data) -> [Self]? { return nil }
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 배열 생성후 반환
     - 미사용
     */
    static func makeRecords(from data: Data, encoding: String.Encoding) -> [Self]? { return nil }
}

// MARK: - File Header Struct -
/// Zip File Header 구조체
internal struct ZipFileHeader: ZipInformationConvertible {
    
    var length: Int

    var localFileHeaderSignature: UInt32
    var versionNeededToExtract: UInt16
    var generalPurposeBitFlag: UInt16
    var compressionMethod: UInt16
    var fileLastModificationTime: UInt16
    var fileLastModificationDate: UInt16
    var crc32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var fileNameLength: UInt16
    var extraFieldLength: UInt16

    /**
     특정 데이터에서 Zip File Header 구조체 생성후 반환
     */
    static func make(from data: Data, encoding: String.Encoding?) -> ZipFileHeader? {
        var offset = 0
        var signature = [UInt8].init(repeating: 0, count: 4)
        // local file header signature 여부를 확인한다
        data[0 ..< 4].copyBytes(to: &signature, count: 4)
        guard signature == LocalFileHeaderSignature else { return nil }

        guard let localFileHeaderSignature: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let versionNeededToExtract: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let generalPurposeBitFlag: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let compressionMethod: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let fileLastModificationTime: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let fileLastModificationDate: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let crc32: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let compressedSize: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let uncompressedSize: UInt32 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let fileNameLength: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }
        guard let extraFieldLength: UInt16 = self.getValue(from: data, offset: &offset) else { return nil }

        return Self.init(length: offset,
                         localFileHeaderSignature: localFileHeaderSignature,
                         versionNeededToExtract: versionNeededToExtract,
                         generalPurposeBitFlag: generalPurposeBitFlag,
                         compressionMethod: compressionMethod,
                         fileLastModificationTime: fileLastModificationTime,
                         fileLastModificationDate: fileLastModificationDate,
                         crc32: crc32,
                         compressedSize: compressedSize,
                         uncompressedSize: uncompressedSize,
                         fileNameLength: fileNameLength,
                         extraFieldLength: extraFieldLength)
    }
}

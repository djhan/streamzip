//
//  StreamZipStructures.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

// MARK: - Zip Information Protocol -
protocol ZipInformationConvertible {
    /**
     Data 기반으로 Zip 정보 구조체 배열 생성후 반환
     */
    static func makeRecords(from data: Data) -> [Self]?
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 배열 생성후 반환
     */
    static func makeRecords(from data: Data, encoding: String.Encoding) -> [Self]?
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
        - encoding: `String.Encoding`
     - Returns: 자기 자신의 struct를 반환. 실패시 nil 반환
     */
    static func make(from data: Data, encoding: String.Encoding) -> Self?

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
     data로부터 데이터를 잘라내서 반환
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
struct ZipEndRecord: ZipInformationConvertible {
    //var endOfCentralDirectorySignature: UInt32
    var numberOfThisDisk: UInt16
    var diskWhereCentralDirectoryStarts: UInt16
    var numberOfCentralDirectoryRecordsOnThisDisk: UInt16
    var totalNumberOfCentralDirectoryRecords: UInt16
    var sizeOfCentralDirectory: UInt32
    var offsetOfStartOfCentralDirectory: UInt32
    var zipFileCommentLength: UInt16
    var comment: String?
    
    /**
     Data 기반으로 Zip 정보 구조체 생성후 반환
     */
    static func make(from data: Data) -> Self? {
        self.make(from: data, encoding: .utf8)
    }
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 생성후 반환
     */
    static func make(from data: Data, encoding: String.Encoding) -> Self? {
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
            comment = String.init(data: commentData, encoding: encoding)
        }
        
        return Self.init(numberOfThisDisk: numberOfThisDisk,
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

// MARK: - Central Directory Struct -
/// Zip Directory Record 구조체
struct ZipDirectoryRecord: ZipInformationConvertible {
    //var centralDirectoryFileHeaderSignature: UInt32
    var versionMadeBy: UInt16
    var versionNeededToExtract: UInt16
    var generalPurposeBitFlag: UInt16
    var compressionMethod: UInt16
    //var fileLastModificationTime: UInt16
    //var fileLastModificationDate: UInt16
    var crc32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var fileNameLength: UInt16
    var extraFieldLength: UInt16
    var fileCommentLength: UInt16
    var diskNumberWhereFileStarts: UInt16
    //var internalFileAttributes: UInt16
    //var externalFileAttributes: UInt32
    //var relativeOffsetOfLocalFileHeader: UInt32
    
    var fileName: String?
    var extraField: String?
    var fileComment: String?

    var modificationDate: Date?
    
    // 전체 길이
    var length: Int

    /**
     Data 기반으로 Zip 정보 구조체 배열 생성후 반환
     */
    static func makeRecords(from data: Data) -> [Self]? {
        return self.makeRecords(from: data, encoding: .utf8)
    }
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 배열 생성후 반환
     */
    static func makeRecords(from data: Data, encoding: String.Encoding) -> [Self]? {
        var offset = 0
        var records: [Self]?
        
        repeat {
            // 최초 4바이트가 CentralDirectorySignature에 해당되는지 확인. 아닌 경우 nil 반환
            var signature = [UInt8].init(repeating: 0, count: 4)
            data[offset ..< offset + 4].copyBytes(to: &signature, count: 4)
            guard signature == CentralDirectorySignature else { break }

            guard let centralDirectoryFileHeaderSignature: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let versionMadeBy: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let versionNeededToExtract: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let generalPurposeBitFlag: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let compressionMethod: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            //guard let fileLastModificationTime: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            //guard let fileLastModificationDate: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let fileLastModificationTimeData = self.getData(from: data, offset: &offset, length: sizeof(UInt16.self)) else { break }
            guard let fileLastModificationDateData = self.getData(from: data, offset: &offset, length: sizeof(UInt16.self)) else { break }
            guard let crc32: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let compressedSize: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let uncompressedSize: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let fileNameLength: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let extraFieldLength: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let fileCommentLength: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let diskNumberWhereFileStarts: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let internalFileAttributes: UInt16 = self.getValue(from: data, offset: &offset) else { break }
            guard let externalFileAttributes: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let relativeOffsetOfLocalFileHeader: UInt32 = self.getValue(from: data, offset: &offset) else { break }
            guard let fileNameData = self.getData(from: data, offset: &offset, length: Int(fileNameLength)) else { break }

            // 순서대로 UInt8 배열이 되기 때문에, little Endian으로 바꾸려면 역순환이 필요하다
            let modificatoinTimeArray = [UInt8](fileLastModificationTimeData)
            let modificatoinDateArray = [UInt8](fileLastModificationDateData)

            // 파일명 생성
            let fileName = String.init(data: fileNameData, encoding: encoding)
            // extra field 생성
            var extraField: String?
            if let extraFieldData = self.getData(from: data, offset: &offset, length: Int(extraFieldLength)) {
                extraField = String.init(data: extraFieldData, encoding: encoding)
            }
            // comment 생성
            var fileComment: String?
            if let fileCommentData = self.getData(from: data, offset: &offset, length: Int(fileCommentLength)) {
                fileComment = String.init(data: fileCommentData, encoding: encoding)
            }

            let record = Self.init(versionMadeBy: versionMadeBy,
                                   versionNeededToExtract: versionNeededToExtract,
                                   generalPurposeBitFlag: generalPurposeBitFlag,
                                   compressionMethod: compressionMethod,
                                   crc32: crc32,
                                   compressedSize: compressedSize,
                                   uncompressedSize: uncompressedSize,
                                   fileNameLength: fileNameLength,
                                   extraFieldLength: extraFieldLength,
                                   fileCommentLength: fileCommentLength,
                                   diskNumberWhereFileStarts: diskNumberWhereFileStarts,
                                   fileName: fileName ,
                                   extraField: extraField,
                                   fileComment: fileComment,
                                   modificationDate: nil,
                                   length: offset)

            if records == nil { records = [Self]() }
            records?.append(record)
        } while (offset < data.count)
        // records 배열을 반환
        return records
    }

    /**
     Data 기반으로 Zip 정보 구조체 생성후 반환
     - 미사용
     */
    static func make(from data: Data) -> Self? { return nil }
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 생성후 반환
     - 미사용
     */
    static func make(from data: Data, encoding: String.Encoding) -> Self? { return nil }
}

// MARK: - File Header Struct -
/// Zip File Header 구조체
struct ZipFileHeader {
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
}

/**
 Data 형 Time과 Date 을 Date로 변환해서 반환
 */
private func GetDate(fromTime timeData: Data, fromDate dateData: Data) -> Date? {
    guard let timeArray = GetSeparate(timeData: timeData),
          let dateArray = GetSeparate(dateData: dateData) else { return nil }
    var dateComponents = DateComponents.init()
    dateComponents.year     = dateArray[0]
    dateComponents.month    = dateArray[1]
    dateComponents.day      = dateArray[2]
    dateComponents.hour     = timeArray[0]
    dateComponents.minute   = timeArray[1]
    dateComponents.second   = timeArray[2]
    return dateComponents.date
}
/**
 Data 형 Time 을 `[Int]` 배열로 변환해서 반환
 - ZIP 파일은 [참고 사이트](https://jmoon.co.kr/48) 에서 설명한 것처럼 A2BC(little endian)의 값을 2진법 표시 후, 자리씩 묶어서 10진법으로 바꾼 것이 각각 시간/분/초(연/월/일)에 대응한다
 */
private func GetSeparate(timeData: Data) -> [Int]? {
    let timeArray = [UInt8](timeData)
    // little Endian이므로 뒷쪽부터 차례로 2진법으로 변환
    let timeBinary = timeArray.reversed().reduce("") { (firstString, second) -> String in
        return firstString + String(second, radix: 2)
    }
    let hourRange = timeBinary.startIndex ... timeBinary.index(timeBinary.startIndex, offsetBy: 5)
    let minRange = hourRange.upperBound ... timeBinary.index(hourRange.upperBound, offsetBy: 6)
    let secRange = minRange.upperBound ... timeBinary.endIndex
    guard let hour = Int(timeBinary[hourRange]),
          let minute = Int(timeBinary[minRange]),
          let second = Int(timeBinary[secRange])  else { return nil }
    return [hour, minute, second * 2]
}
/**
 Data 형 Date 을 `[Int]` 배열로 변환해서 반환
 - ZIP 파일은 [참고 사이트](https://jmoon.co.kr/48) 에서 설명한 것처럼 A2BC(little endian)의 값을 2진법 표시 후, 자리씩 묶어서 10진법으로 바꾼 것이 각각 시간/분/초(연/월/일)에 대응한다
 */
private func GetSeparate(dateData: Data) -> [Int]? {
    let dateArray = [UInt8](dateData)
    // little Endian이므로 뒷쪽부터 차례로 2진법으로 변환
    let dateBinary = dateArray.reversed().reduce("") { (firstString, second) -> String in
        return firstString + String(second, radix: 2)
    }
    let yearRange = dateBinary.startIndex ... dateBinary.index(dateBinary.startIndex, offsetBy: 6)
    let monthRange = yearRange.upperBound ... dateBinary.index(yearRange.upperBound, offsetBy: 4)
    let dayRange = monthRange.upperBound ... dateBinary.endIndex
    guard let year = Int(dateBinary[yearRange]),
          let month = Int(dateBinary[monthRange]),
          let day = Int(dateBinary[dayRange])  else { return nil }
    return [year + 1980, month, day]
}

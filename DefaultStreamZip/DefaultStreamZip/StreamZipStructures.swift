//
//  StreamZipStructures.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

import CommonLibrary

/**
 
 # Zip 파일의 해석 및 압축 해제 순서
 
 1) 파일의 끝 부분에서 End of Central Directory 를 찾아서 ZipEndRecord 를 생성
 2) offsetOfStartOfCentralDirectory 를 구한다
 3) 파일을 처음부터 순환하며 CentralDirectorySignature 위치를 확인, CentralDirectory를 가져와서 StreamZipEntry 구조체를 생성한다
 4) 특정 파일의 압축 해제가 필요한 경우, 해당 StreamZipEntry의 LocalFileHeader를 확인, 압축 방식과 압축 데이터 길이를 확인해 압축을 해제한다
 
 */

/// End of Central Directory signature
let EndOfCentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x05, 0x06]
/// 개별 Central Directory signature
let CentralDirectorySignature: Array<UInt8> = [0x50, 0x4b, 0x01, 0x02]
/// 개별 Local File Header signature
let LocalFileHeaderSignature: Array<UInt8> = [0x50, 0x4b, 0x03, 0x04]


// MARK: - Typealiases -

/**
 Data Request 완료 핸들러
 - Parameters:
     - data: `Data`. 미발견시 nil 반환
     - error: 에러. 옵셔널
 */
public typealias StreamZipDataRequestCompletion = (_ data: Data?, _ error: Error?) -> Void
/**
 Image Request 완료 핸들러
 - Parameters:
     - image: `NSImage`. 미발견시 nil 반환
     - filePath: `String`. 미발견시 nil 반환
     - error: 에러. 옵셔널
 */
public typealias StreamZipImageRequestCompletion = (_ image: NSImage?, _ filepath: String?, _ error: Error?) -> Void
/**
 Thumbnail Image Request 완료 핸들러
 - Parameters:
     - thumbnail: `CGImage`. 미발견 또는 생성 실패시 nil 반환
     - filePath: `String`. 미발견시 nil 반환
     - error: 에러. 옵셔널
 */
public typealias StreamZipThumbnailRequestCompletion = (_ thumbnail: CGImage?, _ filepath: String?, _ error: Error?) -> Void

/**
 FileLength 완료 핸들러
 - Parameters:
     - fileLength: 파일 길이. `UInt64`
     - error: 에러. 옵셔널
 */
public typealias StreamZipFileLengthCompletion = (_ fileLength: UInt64, _ error: Error?) -> Void

/**
 Contents of Directory 완료 핸들러
 - Parameters:
     - contentsOfDirectory: `[ContentOfDirectory]`. 실패시 nil
     - error: 에러. 옵셔널
 */
public typealias ContentsOfDirectoryCompletion = (_ contentsOfDirectory: [ContentOfDirectory]?, _ error: Error?) -> Void

/**
 Archive 해제 완료 핸들러
 - Parameters:
     - fileLength: 파일 길이. `UInt64`
     - entries: `StreamZipEntry` 배열. 옵셔널
     - error: 에러. 옵셔널
 */
public typealias StreamZipArchiveCompletion = (_ fileLength: UInt64, _ entries: [StreamZipEntry]?, _ error: Error?) -> Void
/**
 Entry 생성 완료 핸들러
 - Parameters:
     - entry: `StreamZipEntry`
     - error: 에러. 옵셔널
 */
public typealias StreamZipFileCompletion = (_ entry: StreamZipEntry, _ error: Error?) -> Void


// MARK: - Content of Directory Struct -
/// 디렉토리 하위 Content 구조체
/// - 파일 경로와 길이 등 최소한의 정보만 격납한다
public struct ContentOfDirectory {
    /// 경로
    public var path: String
    /// 파일명 반환
    public var fileName: String {
        return (self.path as NSString).lastPathComponent
    }
    /// 디렉토리 여부
    public var isDirectory: Bool
    /// leaf 노드 여부
    public var isLeaf: Bool {
        return !isDirectory
    }
    /// 파일 크기
    public var fileSize: UInt64

    /// 초기화
    /// - [참고 링크](https://stackoverflow.com/questions/54673224/public-struct-in-framework-init-is-inaccessible-due-to-internal-protection-lev) : public 으로 선언된 Strcut는 외부에서 초기화하려면 반드시 public 으로 선언된 초기화 메쏘드를 추가해야 한다
    public init(path: String,
         isDirectory: Bool,
         fileSize: UInt64) {
        self.path = path
        self.isDirectory = isDirectory
        self.fileSize = fileSize
    }
}

// MARK: - Zip Information Protocol -
public protocol ZipInformationConvertible {
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
public extension ZipInformationConvertible {
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
        do {
            let property: T = try data.getValue(from: offset, length: length, endian: .little)
            // offset에 length를 추가한다
            offset += length
            return property
        }
        catch {
            EdgeLogger.shared.archiveLogger.error("\(#function) :: 에러 발생 = \(error.localizedDescription)")
            return nil
        }
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
public struct ZipEndRecord: ZipInformationConvertible {
    
    public var length: Int
    
    public var endOfCentralDirectorySignature: UInt32
    public var numberOfThisDisk: UInt16
    public var diskWhereCentralDirectoryStarts: UInt16
    public var numberOfCentralDirectoryRecordsOnThisDisk: UInt16
    public var totalNumberOfCentralDirectoryRecords: UInt16
    public var sizeOfCentralDirectory: UInt32
    public var offsetOfStartOfCentralDirectory: UInt32
    public var zipFileCommentLength: UInt16
    public var comment: String?
    
    /**
     Data 기반으로 특정 인코딩 정보로 Zip 정보 구조체 생성후 반환
     */
    public static func make(from data: Data, encoding: String.Encoding?) -> Self? {
        var offset = NSNotFound
        var signature = [UInt8].init(repeating: 0, count: 4)
        
        guard data.count > 4 else {
            EdgeLogger.shared.archiveLogger.error("\(#function) :: Data 길이가 4 바이트를 넘지 않기 때문에 처리 불가능.")
            return nil
        }
        
        // 0번째부터 순환하며 end of central directory signature를 찾는다
        for index in 0 ..< data.count - 4  {
            guard data.count >= index + 4 else {
                EdgeLogger.shared.archiveLogger.error("\(#function) :: Data 길이 = \(data.count), index = \(index) 로, 4바이트를 넘는 값이 존재할 수 없는 상황, 중지.")
                break
            }
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
        if zipFileCommentLength > 0,
           data.count >= offset + Int(zipFileCommentLength) {
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
public struct ZipFileHeader: ZipInformationConvertible {
    
    public var length: Int

    public var localFileHeaderSignature: UInt32
    public var versionNeededToExtract: UInt16
    public var generalPurposeBitFlag: UInt16
    public var compressionMethod: UInt16
    public var fileLastModificationTime: UInt16
    public var fileLastModificationDate: UInt16
    public var crc32: UInt32
    public var compressedSize: UInt32
    public var uncompressedSize: UInt32
    public var fileNameLength: UInt16
    public var extraFieldLength: UInt16

    /**
     특정 데이터에서 Zip File Header 구조체 생성후 반환
     */
    public static func make(from data: Data, encoding: String.Encoding?) -> ZipFileHeader? {
        // 도중에 파일이 제거되는 경우를 대비, 0바이트 이상인지 확인한다
        guard data.count > 0,
              data.count >= 4 else { return nil }
        
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

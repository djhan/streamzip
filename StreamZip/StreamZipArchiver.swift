//
//  StreamZipArchiver.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

import FilesProvider
import SftpProvider
import CommonLibrary
import Detector
import zlib
import os.log

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
internal typealias StreamZipFileLengthCompletion = (_ fileLength: UInt64, _ error: Error?) -> Void

/**
 Contents of Directory 완료 핸들러
 - Parameters:
    - contentsOfDirectory: `[ContentOfDirectory]`. 실패시 nil
    - error: 에러. 옵셔널
 */
internal typealias ContentsOfDirectoryCompletion = (_ contentsOfDirectory: [ContentOfDirectory]?, _ error: Error?) -> Void

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


// MARK: - Stream Zip Archiver Class -
/**
 StreamZipArchiver 클래스
 
 - FTP / FTPS 등 네트웍 상의 zip 파일 압축 해제 처리를 전담한다
 
 */
open class StreamZipArchiver {
    
    // MARK: - Properties

    /// Base URL
    //var baseUrl: URL
    
    /// SyncQueue
    private let syncQueue = DispatchQueue(label: "djhan.StreamZipArchiver", attributes: .concurrent)

    // MARK: Local Properties
    /// 로컬 파일 URL
    var fileURL: URL?
    /// 로컬 파일 URL 데이터
    var fileData: Data?
    
    // MARK: FTP Properties
    /// FTP File Provider
    weak var ftpProvider: FTPFileProvider?

    // MARK: SFTP Properties
    /// SFTP File Provider
    weak var sftpProvider: SftpFileProvider?

    // MARK: WebDav Properties
    weak var webDavProvider: WebDAVFileProvider?
    
    /// 연결 타입
    public var connection: StreamZip.Connection = .unknown

    // MARK: - Initialization
    /*
    /**
     URL로 초기화
     - Parameters:
        - baseUrl: `URL` 타입 지정
     */
    public init(_ baseUrl: URL) {
        self.baseUrl = baseUrl
        // 연결 방식 확인
        self.detectConnection()
    }*/
    /**
     FTP 아이템 초기화
     - Parameters:
        - ftpProvider: FTPFileProvider
     */
    public init?(ftpProvider: FTPFileProvider) {
        self.ftpProvider = ftpProvider
        // 연결 방식 확인 불필요, FTP 지정
        self.connection = .ftp
    }
    /**
     SFTP 아이템 초기화
     - Parameters:
        - sftpProvider: SftpFileProvider
     */
    public init?(sftpProvider: SftpFileProvider) {
        self.sftpProvider = sftpProvider
        // 연결 방식 확인 불필요, SFTP 지정
        self.connection = .sftp
    }
    /**
     WebDav 아이템 초기화
     - Parameters:
        - webDavProvider: WebDAVFileProvider?
     */
    public init?(webDavProvider: WebDAVFileProvider) {
        // 연결 방식 확인
        guard let scheme = webDavProvider.baseURL?.scheme else { return nil }
        switch scheme {
        case StreamZip.Connection.scheme(.webdav): self.connection = .webdav
        case StreamZip.Connection.scheme(.webdav_https): self.connection = .webdav_https
        default: return nil
        }
        self.webDavProvider = webDavProvider
    }
    /**
     로컬 아이템 초기화
     - Parameters:
        - fileURL: URL
     */
    public init?(fileURL: URL) {
        self.fileURL = fileURL
        // 연결 방식 확인 불필요, FTP 지정
        self.connection = .local
    }
    /*
    /// 연결 타입 확인
    private func detectConnection() {
        switch self.baseUrl.scheme {
        case StreamZip.Connection.ftp.rawValue: self.connection = .ftp
        case StreamZip.Connection.ftps.rawValue: self.connection = .ftps
        case StreamZip.Connection.sftp.rawValue: self.connection = .sftp
        case StreamZip.Connection.local.rawValue: self.connection = .local
        default: self.connection = .unknown
        }
    }
     */

    // MARK: - Methods
    
    /**
     특정 경로의 zip 파일에 접근, Entries 배열 생성
     - Parameters:
        - path: 파일 경로 지정
        - fileLength: `UInt64` 타입으로 파일 길이 지정. nil로 지정되는 경우 해당 파일이 있는 디렉토리를 검색해서 파일 길이를 알아낸다
        - encoding: `String.Encoding` 형으로 파일명 인코딩 지정. 미지정시 자동 인코딩
        - completion: `StreamZipArchiveCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func fetchArchive(at path: String,
                             fileLength: UInt64? = nil,
                             encoding: String.Encoding? = nil,
                             completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        // fileLength가 주어졌는지 확인
        guard let fileLength = fileLength else {
            // 없는 경우
            
            // Progress 선언
            var progress: Progress?
            
            // 기본 파일 길이를 0으로 리셋
            var fileLength: UInt64 = 0
            
            os_log("StreamZipArchive>%@ :: file 길이 구하기 시작", log: .fileInfo, type: .debug, #function)
            // 파일 길이를 구해온다
            progress = self.getFileLength(at: path) { [weak self] (currentFileLength, error) in
                guard let strongSelf = self else {
                    return completion(0, nil, error)
                }
                // 에러 발생시 종료 처리
                if let error = error {
                    os_log("StreamZipArchive>%@ :: file 길이가 0", log: .fileInfo, type: .debug, #function)
                    return completion(0, nil, error)
                }
                
                fileLength = currentFileLength > 0 ? currentFileLength : 0
                
                // 파일 길이가 0인 경우 종료 처리
                guard fileLength > 0 else {
                    return completion(0, nil, StreamZip.Error.contentsIsEmpty)
                }
                
                if progress?.isCancelled == true {
                    os_log("StreamZipArchive>%@ :: 작업 중지", log: .fileInfo, type: .debug, #function)
                    return completion(0, nil, StreamZip.Error.aborted)
                }
                
                // Progress 전체 개수 증가
                progress?.totalUnitCount += 1
                
                // Central Directory 정보를 찾고 entry 배열 생성
                if let subProgress = strongSelf.makeEntries(at: path, fileLength: fileLength, encoding: encoding, completion: completion) {
                    // 하위 progress로 추가
                    progress?.addChild(subProgress, withPendingUnitCount: 1)
                }
            }
            return progress
        }
        
        os_log("StreamZipArchive>%@ :: 파일 길이 = %li", log: .fileInfo, type: .debug, #function, fileLength)
        // FileLength가 주어진 경우
        let progress = self.makeEntries(at: path, fileLength: fileLength, encoding: encoding, completion: completion)
        return progress
    }

    /**
     Central Directory 정보를 찾아 Entry 배열을 생성하는 private 메쏘드
     - Parameters:
        - path: 파일 경로 지정
        - fileLength: `UInt64`. 파일 길이 지정
        - encoding: `String.Encoding`. 미지정시 자동 인코딩
        - completion: `StreamZipArchiveCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func makeEntries(at path: String,
                             fileLength: UInt64,
                             encoding: String.Encoding? = nil,
                             completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        // 파일 길이가 0인 경우 종료 처리
        guard fileLength > 0 else {
            print("StreamZipArchive>makeEntries(_:completion:): file length가 0")
            completion(0, nil, StreamZip.Error.contentsIsEmpty)
            return nil
        }
        // 4096 바이트보다 짧은 경우도 종료 처리
        guard fileLength >= 4096 else {
            print("StreamZipArchive>makeEntries(_:completion:): file length가 4096 바이트 미만!")
            // 빈 파일로 간주한다
            completion(0, nil, StreamZip.Error.contentsIsEmpty)
            return nil
        }

        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = fileLength - 4096 ..< fileLength
        
        // Progress 선언
        var progress: Progress?
        
        // 해당 범위만큼 데이터를 전송받는다
        progress = self.request(at: path, range: range) { [weak self] (data, error) in
            guard let strongSelf = self else {
                print("StreamZipArchive>makeEntries(_:completion:): self가 nil!")
                return completion(0, nil, error)
            }
            if let error = error {
                print("StreamZipArchive>makeEntries(_:completion:): 최초 마지막 4096 바이트 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(0, nil, error)
            }
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>makeEntries(_:completion:): 사용자 중지 발생")
                return completion(0, nil, StreamZip.Error.aborted)
            }
            guard let data = data,
                  data.count > 4 else {
                print("StreamZipArchive>makeEntries(_:completion:): 에러가 없는데 데이터 크기가 4바이트 이하. End of Central Directory가 없는 것일 수 있음")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // End of Central Directory 정보 레코드를 가져온다
            guard let zipEndRecord = ZipEndRecord.make(from: data, encoding: encoding) else {
                print("StreamZipArchive>makeEntries(_:completion:): end of central directory 구조체 초기화 실패!")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // Central Directory 시작 offset과 size을 가져온다
            let offsetOfCentralDirectory = UInt64(zipEndRecord.offsetOfStartOfCentralDirectory)
            let sizeOfCentralDirectory = UInt64(zipEndRecord.sizeOfCentralDirectory)
            let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory
                    
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>makeEntries(_:completion:): 이미지 파일이 없음")
                return completion(0, nil, StreamZip.Error.aborted)
            }

            // Progress 전체 개수 증가
            progress?.totalUnitCount += 1

            // Central Directory data 를 가져온다
            let subProgress = strongSelf.request(at: path, range: centralDirectoryRange) { (data, error) in
                if let error = error {
                    print("StreamZipArchive>makeEntries(_:completion:): central directory data 전송중 에러 발생 = \(error.localizedDescription)")
                    return completion(0, nil, error)
                }
                guard let data = data else {
                    print("StreamZipArchive>makeEntries(_:completion:): 에러가 없는데 central directory data 크기가 0")
                    return completion(0, nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                guard let entries = StreamZipEntry.makeEntries(from: data, encoding: encoding) else {
                    print("StreamZipArchive>makeEntries(_:completion:): Stream Zip Entries 생성에 실패")
                    return completion(0, nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                // 완료 처리
                completion(fileLength, entries, nil)
            }
            
            if subProgress != nil {
                // progress에 하위 Progress로 추가
                progress?.addChild(subProgress!, withPendingUnitCount: 1)
            }
        }
        
        return progress
    }
    /**
     특정 Entry의 파일 다운로드 및 압축 해제
     - 다운로드후 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
     - Parameters:
        - path: 파일 경로 지정
        - fileLength: `UInt64`. 파일 길이 지정
        - entry: 압축 해제를 하고자 하는 `StreamZipEntry`
        - encoding: `String.Encoding`. 미지정시 자동 인코딩
        - completion: `StreamZipFileCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func fetchFile(at path: String,
                          fileLength: UInt64,
                          entry: StreamZipEntry,
                          encoding: String.Encoding? = nil,
                          completion: @escaping StreamZipFileCompletion) -> Progress? {
        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
    
        let lowerBound = UInt64(entry.offset)
        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt64(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let uppderbound = lowerBound + length > fileLength ? fileLength : lowerBound + length
        // 다운로드 범위를 구한다
        let range = lowerBound ..< uppderbound
        print("StreamZipArchive>fetchFile(_:completion:): \(path) >> offset = \(lowerBound), length = \(length)")
        // 해당 범위의 데이터를 받아온다
        return self.request(at: path, range: range) { (data, error) in
            if let error = error {
                print("StreamZipArchive>fetchFile(_:completion:): 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(entry, error)
            }
            guard let data = data else {
                print("StreamZipArchive>fetchFile(_:completion:): 에러가 없는데 데이터 크기가 0")
                return completion(entry, StreamZip.Error.contentsIsEmpty)
            }

            // Local Zip File Header 구조체 생성
            guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
                print("StreamZipArchive>fetchFile(_:completion:): local file hedaer를 찾지 못함")
                return completion(entry, StreamZip.Error.localFileHeaderIsFailed)
            }
            
            let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)

            print("StreamZipArchive>fetchFile(_:completion:): \(path) >> data length = \(data.count)")
            print("StreamZipArchive>fetchFile(_:completion:): offset = \(zipFileHeader.length)")
            print("StreamZipArchive>fetchFile(_:completion:): filename length = \(zipFileHeader.fileNameLength)")
            print("StreamZipArchive>fetchFile(_:completion:): extraField length = \(zipFileHeader.extraFieldLength)")
            print("StreamZipArchive>fetchFile(_:completion:): uncompressed size = \(zipFileHeader.uncompressedSize)")

            switch entry.method {
            // Defalte 방식인 경우
            case Z_DEFLATED:
                do {
                    // 성공 처리
                    let decompressData = try data.unzip(offset: offset,
                                                        compressedSize: entry.sizeCompressed,
                                                        crc32: entry.crc32)
                    entry.data = decompressData
                    return completion(entry, nil)
                }
                catch {
                    print("StreamZipArchive>fetchFile(_:completion:): 해제 도중 에러 발생 = \(error.localizedDescription)")
                    return completion(entry, error)
                }
                
            // 비압축시
            case 0:
                // upperBound가 현재 데이터 길이를 초과하지 않도록 조절한다
                // 이상하지만, uncompressedSize를 더한 값이 데이터 길이를 초과하는 경우가 있다
                // 아마도 잘못 만들어진 zip 파일인 것으로 추정된다
                let upperBound = offset + entry.sizeUncompressed > data.count ? data.count : offset + entry.sizeUncompressed
                entry.data = data[offset ..< upperBound]
                return completion(entry, nil)

            // 그 외의 경우
            default:
                print("StreamZipArchive>fetchFile(_:completion:): 미지원 압축 해제 방식. 데이터 해제 불가")
                return completion(entry, StreamZip.Error.unsupportedCompressMethod)
            }
        }
    }
    
    /**
     Local URL에서 Central Directory 정보를 찾아 Entry 배열을 생성하는 메쏘드
     - Parameters:
        - fileLength: `UInt64`. 파일 길이 지정
        - encoding: `String.Encoding`. 미지정시 자동 인코딩
        - completion: `StreamZipArchiveCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func makeEntriesAtLocal(encoding: String.Encoding? = nil,
                                   completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        guard let fileURL = self.fileURL else {
            return nil
        }
        
        do {
            // 데이터 초기화
            self.fileData = try Data.init(contentsOf: fileURL)
            
            guard let fileData = self.fileData else {
                print("StreamZipArchive>makeEntriesAtLocal(_:completion:): file data가 nil!")
                return nil
            }
            
            // 파일 길이가 0인 경우 종료 처리
            let fileLength = fileData.count
            guard fileLength > 0 else {
                print("StreamZipArchive>makeEntriesAtLocal(_:completion:): file length가 0")
                completion(0, nil, StreamZip.Error.contentsIsEmpty)
                return nil
            }
            
            // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
            let range = fileLength - 4096 ..< fileLength

            guard Int(range.lowerBound) + range.count <= fileLength else {
                completion(UInt64(fileLength), nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
                return nil
            }
            
            let endOfCentralData = fileData.subdata(in: range)
            guard endOfCentralData.count > 4 else {
                      print("StreamZipArchive>makeEntriesAtLocal(_:completion:): 에러가 없는데 데이터 크기가 4바이트 이하. End of Central Directory가 없는 것일 수 있음")
                      completion(UInt64(fileLength), nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
                      return nil
            }
            
            // End of Central Directory 정보 레코드를 가져온다
            guard let zipEndRecord = ZipEndRecord.make(from: endOfCentralData, encoding: encoding) else {
                print("StreamZipArchive>makeEntriesAtLocal(_:completion:): end of central directory 구조체 초기화 실패!")
                completion(UInt64(fileLength), nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
                return nil
            }
            
            // Central Directory 시작 offset과 size을 가져온다
            let offsetOfCentralDirectory = Int(zipEndRecord.offsetOfStartOfCentralDirectory)
            let sizeOfCentralDirectory = Int(zipEndRecord.sizeOfCentralDirectory)
            let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory

            let centralDirectoryData = fileData.subdata(in: centralDirectoryRange)
            
            guard let entries = StreamZipEntry.makeEntries(from: centralDirectoryData, encoding: encoding) else {
                print("StreamZipArchive>makeEntriesAtLocal(_:completion:): Stream Zip Entries 생성에 실패")
                completion(0, nil, StreamZip.Error.centralDirectoryIsFailed)
                return nil
            }
            // 완료 처리
            completion(UInt64(fileLength), entries, nil)
            return nil
        }
        catch let error {
            completion(0, nil, error)
            return nil
        }
        
        let progress = Progress.init(totalUnitCount: 1)
        
        
        
        return progress
    }
    /**
     로컬 URL에서 특정 Entry의 압축 해제
     - 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
     - Parameters:
        - fileLength: `UInt64`. 파일 길이 지정
        - entry: 압축 해제를 하고자 하는 `StreamZipEntry`
        - encoding: `String.Encoding`. 미지정시 자동 인코딩
        - completion: `StreamZipFileCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func getFileAtLocal(fileLength: UInt64,
                               entry: StreamZipEntry,
                               encoding: String.Encoding? = nil,
                               completion: @escaping StreamZipFileCompletion) -> Progress? {
        guard let fileData = self.fileData else {
            print("StreamZipArchive>getFileAtLocal(_:completion:): fileData 미생성!")
            return nil
        }
        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
    
        let lowerBound = UInt64(entry.offset)
        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt64(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let uppderbound = lowerBound + length > fileLength ? fileLength : lowerBound + length
        // 데이터 범위를 구한다
        let range = lowerBound ..< uppderbound
        print("StreamZipArchive>getFileAtLocal(_:completion:): offset = \(lowerBound), length = \(length)")
        // 해당 범위의 데이터를 가져온다
        
    }
    
    // MARK: Process Entry Data
    /**
     Entry 데이터 처리 및 완료 처리
     - Parameters:
        - entry: 데이터를 가져온 `StreamZipEntry`
        - encoding:`String.Encoding`
        - data: 가져온 Entry 데이터. 옵셔널
        - error: 에러값. 옵셔널
        - completion: 완료 핸들러
     */
    private func processEntryData(at entry: StreamZipEntry,
                                  encoding: String.Encoding? = nil,
                                  data: Data?,
                                  error: Error?,
                                  completion: @escaping StreamZipFileCompletion) {
        if let error = error {
            print("StreamZipArchive>fetchFile(_:completion:): 데이터 전송중 에러 발생 = \(error.localizedDescription)")
            return completion(entry, error)
        }
        guard let data = data else {
            print("StreamZipArchive>fetchFile(_:completion:): 에러가 없는데 데이터 크기가 0")
            return completion(entry, StreamZip.Error.contentsIsEmpty)
        }

        // Local Zip File Header 구조체 생성
        guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
            print("StreamZipArchive>fetchFile(_:completion:): local file hedaer를 찾지 못함")
            return completion(entry, StreamZip.Error.localFileHeaderIsFailed)
        }
        
        let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)

        print("StreamZipArchive>fetchFile(_:completion:): offset = \(zipFileHeader.length)")
        print("StreamZipArchive>fetchFile(_:completion:): filename length = \(zipFileHeader.fileNameLength)")
        print("StreamZipArchive>fetchFile(_:completion:): extraField length = \(zipFileHeader.extraFieldLength)")
        print("StreamZipArchive>fetchFile(_:completion:): uncompressed size = \(zipFileHeader.uncompressedSize)")

        switch entry.method {
        // Defalte 방식인 경우
        case Z_DEFLATED:
            do {
                // 성공 처리
                let decompressData = try data.unzip(offset: offset,
                                                    compressedSize: entry.sizeCompressed,
                                                    crc32: entry.crc32)
                entry.data = decompressData
                return completion(entry, nil)
            }
            catch {
                print("StreamZipArchive>fetchFile(_:completion:): 해제 도중 에러 발생 = \(error.localizedDescription)")
                return completion(entry, error)
            }
            
        // 비압축시
        case 0:
            // upperBound가 현재 데이터 길이를 초과하지 않도록 조절한다
            // 이상하지만, uncompressedSize를 더한 값이 데이터 길이를 초과하는 경우가 있다
            // 아마도 잘못 만들어진 zip 파일인 것으로 추정된다
            let upperBound = offset + entry.sizeUncompressed > data.count ? data.count : offset + entry.sizeUncompressed
            entry.data = data[offset ..< upperBound]
            return completion(entry, nil)

        // 그 외의 경우
        default:
            print("StreamZipArchive>fetchFile(_:completion:): 미지원 압축 해제 방식. 데이터 해제 불가")
            return completion(entry, StreamZip.Error.unsupportedCompressMethod)
        }
    }
    
    // MARK: Image
    /**
     아카이브 중 최초 이미지를 반환
     - 인코딩된 파일명 순서로 정렬, 그 중에서 최초의 이미지 파일을 반환한디
     - Parameters:
        - path: 파일 경로 지정
        - fileLength: `UInt64` 타입으로 파일 길이 지정. nil로 지정되는 경우 해당 파일이 있는 디렉토리를 검색해서 파일 길이를 알아낸다
        - encoding: 파일명 인코딩 지정. 미지정시 자동 인코딩
        - completion: `StreamZipImageRequestCompletion` 타입으로 이미지 및 에러 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func firstImage(at path: String,
                           fileLength: UInt64? = nil,
                           encoding: String.Encoding? = nil,
                           completion: @escaping StreamZipImageRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        print("StreamZipArchive>getFirstImage(encoding:completion:): 첫 번째 이미지를 가져오기 위한 시도...")
        progress = self.fetchArchive(at: path, fileLength: fileLength, encoding: encoding) { [weak self] (fileLength, entries, error) in
            guard let strongSelf = self else {
                print("StreamZipArchive>getFirstImage(encoding:completion:): self가 nil!")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            // 에러 발생시
            if let error = error {
                print("StreamZipArchive>getFirstImage(encoding:completion:): 에러 발생 = \(error.localizedDescription)")
                return completion(nil, nil, error)
            }
            guard var entries = entries else {
                print("StreamZipArchive>getFirstImage(encoding:completion:): entry가 0개")
                return completion(nil, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            // entry를 이름순으로 정렬
            entries.sort { $0.filePath < $1.filePath }
                
            var targetEntry: StreamZipEntry?
            for entry in entries {
                guard let utiString = entry.filePath.utiString else { continue }
                if Detector.shared.detectImageFormat(utiString) == .unknown { continue }
                // 이미지 entry 발견시, 대입
                targetEntry = entry
                break
            }
                        
            guard let entry = targetEntry else {
                print("StreamZipArchive>getFirstImage(encoding:completion:): 이미지 파일이 없음")
                return completion(nil, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>getFirstImage(encoding:completion:):작업 중지 처리")
                return completion(nil, nil, StreamZip.Error.aborted)
            }

            // Progress 전체 개수 증가
            progress?.totalUnitCount += 1

            let subProgress = strongSelf.fetchFile(at: path, fileLength: fileLength, entry: entry, encoding: encoding) { (resultEntry, error) in
                // 에러 발생시
                if let error = error {
                    print("StreamZipArchive>getFirstImage(encoding:completion:): \(resultEntry.filePath) >> 전송중 에러 발생 = \(error.localizedDescription)")
                    return completion(nil, nil, error)
                }
                guard let data = resultEntry.data,
                      let image = NSImage.init(data: data) else {
                    print("StreamZipArchive>getFirstImage(encoding:completion:): data가 nil, 또는 image가 아님")
                    return completion(nil, nil, StreamZip.Error.contentsIsEmpty)
                }

                return completion(image, resultEntry.filePath, nil)
            }
            if subProgress != nil {
                progress?.addChild(subProgress!, withPendingUnitCount: 1)
            }
        }
        
        return progress
    }

    /**
     압축 파일 썸네일 이미지 반환
     - 그룹 환경설정에서 배너 표시가 지정된 경우 배너까지 추가
     - 지정된 크기로 썸네일 생성, CGImage 타입으로 완료 핸들러로 반환한다
     
     - Parameters:
        - path: 파일 경로 지정
        - fileLength: `UInt64` 타입으로 파일 길이 지정. nil로 지정되는 경우 해당 파일이 있는 디렉토리를 검색해서 파일 길이를 알아낸다
        - size: 최대 크기 지정
        - completion: `StreamZipThumbnailRequestCompletion` 타입. CGImage, filePath, error 를 반환한다.
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func thumbnail(at path: String,
                          fileLength: UInt64? = nil,
                          size: NSSize,
                          completion: @escaping StreamZipThumbnailRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        
        print("StreamZipArchive>thumbnail(completion:): \(path) >> 썸네일 이미지를 가져온다")
        progress = self.firstImage(at: path, fileLength: fileLength, encoding: nil) { [weak self] (image, filePath, error) in
            guard let strongSelf = self else {
                print("StreamZipArchive>thumbnail(completion:): self가 nil!")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            // 에러 발생시
            if let error = error {
                print("StreamZipArchive>thumbnail(completion:): 에러 발생 = \(error.localizedDescription)")
                return completion(nil, nil, error)
            }
            
            print("StreamZipArchive>thumbnail(completion:): \(path) >> 드로잉 개시")

            // progress 작업 개수 1 증가
            progress?.totalUnitCount += 1
            
            let preference = GroupPreference.shared
            
            // 512 x 512 기준으로 canvasFrame / targetFrame을 구한다
            guard let image = image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let targetFrameRects = getThumbnailTargetRects(image,
                                                                 minCroppingRatio: preference.minCroppingRatio,
                                                                 maxCroppingRatio: preference.maxCroppingRatio,
                                                                 maximumSize: size) else {
                print("StreamZipArchive>thumbnail(completion:): cgimage로 변환하는데 실패한 것으로 추정됨")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            
            guard let cgcontext = strongSelf.offscreenCGContext(with: targetFrameRects.canvasFrame.size, buffer: nil) else {
                print("StreamZipArchive>thumbnail(completion:): cgcontext 생성에 실패")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            
            let canvasFrame = targetFrameRects.canvasFrame
            let targetFrame = targetFrameRects.targetFrame
            
            // 배경을 흰색으로 채운다
            cgcontext.setFillColor(NSColor.white.cgColor)
            cgcontext.fill(canvasFrame)
            
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>thumbnail(completion:): 작업 중지")
                return completion(nil, nil, StreamZip.Error.aborted)
            }
            
            // 이미지를 드로잉
            cgcontext.draw(cgImage, in: targetFrame)
            // 배너 필요시 드로잉
            if preference.showExtensionBanner == true {
                let banner = (path as NSString).pathExtension
                if banner.length > 0 {
                    drawBanner(banner,
                               bannerHeightRatio: preference.bannerHeightRatio,
                               maximumSize: size,
                               inContext: cgcontext,
                               isActiveContext: false,
                               inCanvas: canvasFrame)
                }
            }
            
            // 외곽선 드로잉
            cgcontext.setStrokeColor(NSColor.lightGray.cgColor)
            cgcontext.stroke(canvasFrame, width: 0.5)

            // cgImage를 생성
            guard let thumbnailCGImage = cgcontext.makeImage() else {
                print("StreamZipArchive>thumbnail(completion:): cgImage 생성에 실패")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
       
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>thumbnail(completion:): 작업 중지")
                return completion(nil, nil, StreamZip.Error.aborted)
            }

            // progress 종료 처리
            progress?.completedUnitCount += 1
            
            // CGImage 반환 처리
            return completion(thumbnailCGImage, filePath, nil)
        }
        
        return progress
    }
    
    /**
     오프스크린 컨텍스트를 생성, 반환
     - Parameters:
        - size: CGSize
        - buffer: 이미지 버퍼. `UnsafeMutableRawPointer`. 보통 nil로 지정
    - Returns: CGContext. 생성 실패시 nil 반환
     */
    private func offscreenCGContext(with size: CGSize, buffer: UnsafeMutableRawPointer?) -> CGContext? {
        return autoreleasepool { () -> CGContext? in
            
            let width: Int  = Int(size.width)
            let height: Int = Int(size.height)

            var colorSpace: CGColorSpace?
            var bitmapInfo: UInt32?

            // 컬러 컨텍스트를 반환한다
            colorSpace = CGColorSpaceCreateDeviceRGB()
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            // rgba(4)를 곱해서 bytesPerRaw를 구한다
            let bytesPerRow = width * 4
            let context = CGContext.init(data: buffer,
                                         width: width,
                                         height: height,
                                         bitsPerComponent: 8,
                                         bytesPerRow: bytesPerRow,
                                         // 강제 옵셔널 벗기기 적용
                                         space: colorSpace!,
                                         bitmapInfo: bitmapInfo!)
            return context
        }
    }

    
    // MARK: Download Data
    
    /**
     특정 경로의 FileLength를 구하는 메쏘드
     - 완료 핸들러로 FileLength를 반환
     - Parameters:
        - path: 파일 경로
        - completion: `StreamZipFileLengthCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getFileLength(at path: String, completion: @escaping StreamZipFileLengthCompletion) -> Progress? {
        //----------------------------------------------------------------------------------------------//
        /// 작업 종료용 내부 메쏘드
        func complete(_ contentsOfDirectory: [ContentOfDirectory]) {
            // 이미 컨텐츠 목록이 있는 경우
            let filtered = contentsOfDirectory.filter { $0.path.trimmedSlash() == path.trimmedSlash() }
            guard let foundItem = filtered.first else {
                os_log("StreamZipArchive>%@ :: %@ >> contents 미발견", log: .fileInfo, type: .debug, #function, path)
                return completion(0, StreamZip.Error.contentsIsEmpty)
            }
            // 찾아낸 아이템의 크기 반환
            return completion(foundItem.fileSize, nil)
        }
        //----------------------------------------------------------------------------------------------//

        // path의 parent 경로를 구한다
        let parentPath = (path as NSString).deletingLastPathComponent

        // 컨텐츠 목록 생성 실행
        os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록을 가져온다", log: .fileInfo, type: .debug, #function, path)
        // progress 지정
        var progress: Progress?
        progress = self.getContentsOfDirectory(at: parentPath) { (contentsOfDirectory, error) in
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, path, error.localizedDescription)
                return completion(0, error)
            }
            
            guard let contentsOfDirectory = contentsOfDirectory else {
                os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록 작성 실패!", log: .fileInfo, type: .debug, path, #function)
                return completion(0, StreamZip.Error.contentsIsEmpty)
            }
            
            // 종료 처리
            complete(contentsOfDirectory)
        }
        return progress
    }
    /**
     contents of directory 배열 생성후 완료 핸들러로 반환
     - Parameters:
        - mainPath: contents 목록을 만들려고 하는 경로
        - completion: `ContentsOfDirectoryCompletion` 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getContentsOfDirectory(at mainPath: String, completion: @escaping ContentsOfDirectoryCompletion) -> Progress? {
        switch self.connection {
        // FTP인 경우
        case .ftp, .ftps: return self.getContentsOfDirectoryInFTP(at: mainPath, completion: completion)
        // SFTP인 경우
        case .sftp: return self.getContentsOfDirectoryInSFTP(at: mainPath, completion: completion)
        // webDav인 경우
        case .webdav, .webdav_https: return self.getContentsOfDirectoryInWebDav(at: mainPath, completion: completion)
        // 그 외: 미지원으로 실패 처리
        default:
            completion(nil, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }

    // MARK: Get Contents of Directory
    /**
     FTP에서 mainPath 대입 후, contents of directory 배열 생성
     - Parameters:
        - mainPath: contents 목록을 만들려고 하는 경로
        - completion: `ContentsOfDirectoryCompletion` 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getContentsOfDirectoryInFTP(at mainPath: String, completion: @escaping ContentsOfDirectoryCompletion) -> Progress? {
 
        guard let ftpProvider = self.ftpProvider else {
            os_log("StreamZipArchive>%@ :: ftpProvider가 nil!", log: .fileInfo, type: .debug, #function)
            completion(nil, StreamZip.Error.unknown)
            return nil
        }
 
        // progress 지정
        var progress: Progress?
        progress = ftpProvider.contentsOfDirectoryWithProgress(path: mainPath) { (ftpItems, error) in
            os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록 작성 완료", log: .fileInfo, type: .debug, #function, mainPath)
            // 에러 발생시 중지
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, mainPath, error.localizedDescription)
                return completion(nil, error)
            }
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 취소 발생", log: .fileInfo, type: .debug, #function, mainPath)
                return completion(nil, StreamZip.Error.aborted)
            }

            // progress 작업 개수 1 증가
            progress?.totalUnitCount += 1
            
            // contents of directory 배열에 아이템 대입
            let contentsOfDirectory = ftpItems.map { (ftpItem) -> ContentOfDirectory in
                // ftpProvider는 디렉토리인 경우 사이즈를 -1로 반환하기 때문에, 0으로 맞춘다
                let size = ftpItem.size > 0 ? ftpItem.size : 0
                return ContentOfDirectory.init(path: ftpItem.path,
                                               isDirectory: ftpItem.isDirectory,
                                               fileSize: UInt64(size))
            }

            // progress 처리 개수 1 증가
            progress?.completedUnitCount += 1
            
            // 완료 처리
            return completion(contentsOfDirectory, nil)
        }
        return progress
    }
    /**
     SFTP에서 mainPath 대입 후, contents of directory 배열 생성
     - Parameters:
        - mainPath: contents 목록을 만들려고 하는 경로
        - completion: `ContentsOfDirectoryCompletion` 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getContentsOfDirectoryInSFTP(at mainPath: String, completion: @escaping ContentsOfDirectoryCompletion) -> Progress? {
 
        guard let sftpProvider = self.sftpProvider else {
            os_log("StreamZipArchive>%@ :: sftpProvider가 nil!", log: .fileInfo, type: .debug, #function)
            completion(nil, StreamZip.Error.unknown)
            return nil
        }
 
        // 컨텐츠 목록 생성 실행
        os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록을 가져온다", log: .fileInfo, type: .debug, #function, mainPath)
        // progress 지정
        var progress: Progress?
        progress = sftpProvider.contentsOfDirectory(at: mainPath) { sftpItems, error in
            os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록 작성 완료", log: .fileInfo, type: .debug, #function, mainPath)
            // 에러 발생시 중지
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, mainPath, error.localizedDescription)
                return completion(nil, error)
            }
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 취소 발생", log: .fileInfo, type: .debug, #function, mainPath)
                return completion(nil, StreamZip.Error.aborted)
            }
            guard let sftpItems = sftpItems else {
                os_log("StreamZipArchive>%@ :: %@ >> 아이템 없음", log: .fileInfo, type: .debug, #function, mainPath)
                return completion(nil, StreamZip.Error.contentsIsEmpty)
            }

            // progress 작업 개수 1 증가
            progress?.totalUnitCount += 1
            
            // contents of directory 배열에 아이템 대입
            let contentsOfDirectory = sftpItems.map { (sftpItem) -> ContentOfDirectory in
                let path = mainPath.appending(sftpItem.filename)
                return ContentOfDirectory.init(path: path,
                                               isDirectory: sftpItem.isDirectory,
                                               fileSize: UInt64(sftpItem.fileSize ?? 0))
            }

            // progress 처리 개수 1 증가
            progress?.completedUnitCount += 1
            
            // 완료 처리
            return completion(contentsOfDirectory, nil)
        }
        return progress
    }
    /**
     WebDav에서 mainPath 대입 후, contents of directory 배열 생성
     - Parameters:
        - mainPath: contents 목록을 만들려고 하는 경로
        - completion: `ContentsOfDirectoryCompletion` 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getContentsOfDirectoryInWebDav(at mainPath: String, completion: @escaping ContentsOfDirectoryCompletion) -> Progress? {
        guard let webDavProvider = self.webDavProvider else {
            os_log("StreamZipArchive>%@ :: webDavProvider가 nil!", log: .fileInfo, type: .debug, #function)
            completion(nil, StreamZip.Error.unknown)
            return nil
        }
 
        // progress 지정
        var progress: Progress?
        progress = webDavProvider.contentsOfDirectoryWithProgress(path: mainPath) { (ftpItems, error) in
            os_log("StreamZipArchive>%@ :: %@ >> 디렉토리 목록 작성 완료", log: .fileInfo, type: .debug, #function, mainPath)
            // 에러 발생시 중지
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, mainPath, error.localizedDescription)
                return completion(nil, error)
            }
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 취소 발생", log: .fileInfo, type: .debug, #function, mainPath)
                return completion(nil, StreamZip.Error.aborted)
            }

            // progress 작업 개수 1 증가
            progress?.totalUnitCount += 1
            
            // contents of directory 배열에 아이템 대입
            let contentsOfDirectory = ftpItems.map { (ftpItem) -> ContentOfDirectory in
                // ftpProvider는 디렉토리인 경우 사이즈를 -1로 반환하기 때문에, 0으로 맞춘다
                let size = ftpItem.size > 0 ? ftpItem.size : 0
                return ContentOfDirectory.init(path: ftpItem.path,
                                               isDirectory: ftpItem.isDirectory,
                                               fileSize: UInt64(size))
            }

            // progress 처리 개수 1 증가
            progress?.completedUnitCount += 1
            
            // 완료 처리
            return completion(contentsOfDirectory, nil)
        }
        return progress
    }
    
    // MARK: Get Data
    /**
     특정 범위 데이터를 가져오는 메쏘드
     - 네트웍에서 사용
     - Parameters:
        - path: 파일 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func request(at path: String, range: Range<UInt64>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        switch self.connection {
        // FTP인 경우
        case .ftp: return self.requestFromFTP(at: path, range: range, completion: completion)
        // SFTP인 경우
        case .sftp: return self.requestFromSFTP(at: path, range: range, completion: completion)
        // WebDav인 경우
        case .webdav, .webdav_https: return self.requestFromWebDav(at: path, range: range, completion: completion)
        // 그 외의 경우
        default:
            // 미지원 연결 방식 에러 반환
            completion(nil, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }
    /**
     FTP로 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - path: 데이터를 가져올 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func requestFromFTP(at path: String, range: Range<UInt64>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        guard let ftpProvider = self.ftpProvider else {
            completion(nil, StreamZip.Error.unknown)
            return nil
        }

        var progress: Progress?
        progress = ftpProvider.contents(path: path,
                                        offset: Int64(range.lowerBound),
                                        length: range.count) { (data, error) in
            // 에러 여부를 먼저 확인
            // 이유: progress?.isCancelled 를 먼저 확인하는 경우, error 가 발생했는데도 사용자 취소로 처리해 버리는 경우가 있기 때문이다
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, path, error.localizedDescription)
                return completion(nil, error)
            }
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 중지 발생", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.aborted)
            }
            guard let data = data else {
                os_log("StreamZipArchive>%@ :: %@ >> 데이터가 없음", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.contentsIsEmpty)
            }

            return completion(data, nil)
        }
        return progress
    }
    /**
     SFTP로 현재 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - path: 데이터를 가져올 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func requestFromSFTP(at path: String, range: Range<UInt64>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        guard let sftpProvider = self.sftpProvider else {
            completion(nil, StreamZip.Error.unknown)
            return nil
        }

        var progress: Progress?
        os_log("StreamZipArchive>%@ :: %@ >> offset = %li, length = %li", log: .fileInfo, type: .debug, #function, path, UInt64(range.lowerBound), UInt64(range.count))
        progress = sftpProvider.contents(at: path,
                                         offset: UInt64(range.lowerBound),
                                         length: UInt64(range.count)) { complete, success, data in
            guard complete == true else {
                // 미완료시
                return
            }
            
            // 성공 여부를 먼저 확인
            guard success == true else {
                os_log("StreamZipArchive>%@ :: %@ >> 작업 실패", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.unknown)
            }
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 중지 발생", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.aborted)
            }
            guard let data = data else {
                os_log("StreamZipArchive>%@ :: %@ >> 데이터가 없음", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.contentsIsEmpty)
            }

            return completion(data, nil)
        }
        return progress
    }
    /**
     WebDav로 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - path: 데이터를 가져올 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func requestFromWebDav(at path: String, range: Range<UInt64>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        guard let webDavProvider = self.webDavProvider else {
            completion(nil, StreamZip.Error.unknown)
            return nil
        }

        var progress: Progress?
        progress = webDavProvider.contents(path: path,
                                           offset: Int64(range.lowerBound),
                                           length: range.count) { (data, error) in
            // 에러 여부를 먼저 확인
            // 이유: progress?.isCancelled 를 먼저 확인하는 경우, error 가 발생했는데도 사용자 취소로 처리해 버리는 경우가 있기 때문이다
            if let error = error {
                os_log("StreamZipArchive>%@ :: %@ >> 에러 발생 = %@", log: .fileInfo, type: .debug, #function, path, error.localizedDescription)
                return completion(nil, error)
            }
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                os_log("StreamZipArchive>%@ :: %@ >> 사용자 중지 발생", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.aborted)
            }
            guard let data = data else {
                os_log("StreamZipArchive>%@ :: %@ >> 데이터가 없음", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.contentsIsEmpty)
            }
            guard data.count == range.count else {
                os_log("StreamZipArchive>%@ :: %@ >> 데이터 길이가 다르다!", log: .fileInfo, type: .debug, #function, path)
                return completion(nil, StreamZip.Error.unknown)
            }

            return completion(data, nil)
        }
        return progress
    }
}


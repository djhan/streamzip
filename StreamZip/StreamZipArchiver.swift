//
//  StreamZipArchiver.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

import FilesProvider
import CommonLibrary
import Detector
import zlib

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
 FileLength 완료 핸들러
 - Parameters:
    - fileLength: 파일 길이. `UInt`
    - error: 에러. 옵셔널
 */
public typealias StreamZipFileLengthCompletion = (_ fileLength: UInt, _ error: Error?) -> Void
/**
 Archive 해제 완료 핸들러
 - Parameters:
    - fileLength: 파일 길이. `UInt`
    - entries: `StreamZipEntry` 배열. 옵셔널
    - error: 에러. 옵셔널
 */
public typealias StreamZipArchiveCompletion = (_ fileLength: UInt, _ entries: [StreamZipEntry]?, _ error: Error?) -> Void
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

    /// URL
    var url: URL
    /// 파일 길이
    private var fileLength: UInt = 0
    
    /// 진행상황
    public var progress: Progress?
        
    /// Stream Zip Entry 배열
    public lazy var entries = [StreamZipEntry]()
    
    // MARK: FTP Properties
    /// FTP File Provider
    weak var ftpProvider: FTPFileProvider?
    /// 실제 파일 경로
    var subPath: String?
    
    /// 연결 타입
    public var connection: StreamZip.Connection = .unknown

    // MARK: - Initialization
    /**
     URL로 초기화
     - Parameters:
        - url: `URL` 타입 지정
     */
    public init(_ url: URL) {
        self.url = url
        // 연결 방식 확인
        self.detectConnection()
    }
    /**
     FTP 아이템 초기화
     - Parameters:
        - ftpProvider: FTPFileProvider
        - subPath: 실제 파일의 하위 경로
     */
    public init?(ftpProvider: FTPFileProvider, subPath: String) {
        guard let url = ftpProvider.baseURL?.appendingPathComponent(subPath) else { return nil }
        self.ftpProvider = ftpProvider
        self.url = url
        self.subPath = subPath
        // 연결 방식 확인 불필요, FTP 지정
        self.connection = .ftp
    }
    
    /// 연결 타입 확인
    private func detectConnection() {
        switch self.url.scheme {
        case StreamZip.Connection.ftp.rawValue: self.connection = .ftp
        case StreamZip.Connection.ftps.rawValue: self.connection = .ftps
        case StreamZip.Connection.sftp.rawValue: self.connection = .sftp
        case StreamZip.Connection.http.rawValue: self.connection = .http
        default: self.connection = .unknown
        }
    }

    // MARK: - Methods
    
    /**
     delegate의 zip 파일에 접근, Entries 배열 생성
     - Parameters:
        - encoding: `String.Encoding` 형으로 파일명 인코딩 지정
        - completion: `StreamZipArchiveCompletion` 완료 핸들러
     */
    public func fetchArchive(encoding: String.Encoding, completion: @escaping StreamZipArchiveCompletion) {
        // 기본 파일 길이를 0으로 리셋
        self.fileLength = 0
        // 파일 길이를 구해온다
        self.getFileLength { [weak self] (fileLength, error) in
            guard let strongSelf = self else {
                return completion(0, nil, error)
            }
            // 에러 발생시 종료 처리
            if let error = error {
                return completion(0, nil, error)
            }
            
            strongSelf.fileLength = fileLength
            
            // 파일 길이가 0인 경우 종료 처리
            guard strongSelf.fileLength > 0 else {
                return completion(0, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            // Central Directory 정보를 찾고 entry 배열 생성
            strongSelf.makeEntries(encoding: encoding, completion: completion)
        }
    }
    
    /**
     Central Directory 정보를 찾아 Entry 배열을 생성하는 내부 메쏘드
     - Parameters:
        - encoding: `String.Encoding`
        - completion: `StreamZipArchiveCompletion`
     */
    private func makeEntries(encoding: String.Encoding, completion: @escaping StreamZipArchiveCompletion) {
        // 파일 길이가 0인 경우 종료 처리
        guard self.fileLength > 0 else {
            print("StreamZipArchive>makeEntries(_:completion:): file length가 0")
            return completion(0, nil, StreamZip.Error.contentsIsEmpty)
        }
        
        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = self.fileLength - 4096 ..< self.fileLength
        // 해당 범위만큼 데이터를 전송받는다
        self.request(range: range) { [weak self] (data, error) in
            guard let strongSelf = self else {
                print("StreamZipArchive>makeEntries(_:completion:): self가 nil!")
                return completion(0, nil, error)
            }
            if let error = error {
                print("StreamZipArchive>makeEntries(_:completion:): 최초 마지막 4096 바이트 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(0, nil, error)
            }
            guard let data = data else {
                print("StreamZipArchive>makeEntries(_:completion:): 에러가 없는데 데이터 크기가 0. End of Central Directory가 없는 것일 수 있음")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // End of Central Directory 정보 레코드를 가져온다
            guard let zipEndRecord = ZipEndRecord.make(from: data, encoding: encoding) else {
                print("StreamZipArchive>makeEntries(_:completion:): end of central directory 구조체 초기화 실패!")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // Central Directory 시작 offset과 size을 가져온다
            let offsetOfCentralDirectory = UInt(zipEndRecord.offsetOfStartOfCentralDirectory)
            let sizeOfCentralDirectory = UInt(zipEndRecord.sizeOfCentralDirectory)
            let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory
            
            // Central Directory data 를 가져온다
            strongSelf.request(range: centralDirectoryRange) { [weak self] (data, error) in
                guard let strongSelf = self else {
                    print("StreamZipArchive>makeEntries(_:completion:): self가 nil!")
                    return completion(0, nil, error)
                }
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
                
                // self.entries 프로퍼티에 생성된 entries를 대입
                strongSelf.entries = entries
                
                // 완료 처리
                completion(strongSelf.fileLength, strongSelf.entries, nil)
            }
        }
    }
    
    /**
     특정 Entry의 파일 다운로드
     - 다운로드후 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
     */
    public func fetchFile(_ entry: StreamZipEntry, encoding: String.Encoding, completion: @escaping StreamZipFileCompletion) {
        
        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
    
        let lowerBound = UInt(entry.offset)
        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let uppderbound = lowerBound + length > self.fileLength ? self.fileLength : lowerBound + length
        // 다운로드 범위를 구한다
        let range = lowerBound ..< uppderbound
        // 해당 범위의 데이터를 받아온다
        self.request(range: range) { (data, error) in
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
            
            switch entry.method {
            // Defalte 방식인 경우
            case Z_DEFLATED:
                do {
                    // 성공 처리
                    let decompressData = try data.unzip(offset:offset, compressedSize: entry.sizeCompressed, crc32: entry.crc32)
                    entry.data = decompressData
                    return completion(entry, nil)
                }
                catch {
                    print("StreamZipArchive>fetchFile(_:completion:): 해제 도중 에러 발생 = \(error.localizedDescription)")
                    return completion(entry, error)
                }
                
            // 비압축시
            case 0:
                entry.data = data[offset ..< offset + entry.sizeUncompressed]
                
            // 그 외의 경우
            default:
                print("StreamZipArchive>fetchFile(_:completion:): 미지원 압축 해제 방식. 데이터 해제 불가")
                return completion(entry, StreamZip.Error.unsupportedCompressMethod)
            }
        }
    }
    
    // MARK: Image
    /**
     아카이브 중 최초 이미지를 반환
     - 인코딩된 파일명 순서로만 정렬 처리
     */
    
    public func firstImage(encoding: String.Encoding, completion: @escaping StreamZipImageRequestCompletion) {
        self.fetchArchive(encoding: encoding) { [weak self] (fileLength, entries, error) in
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
            
            strongSelf.fetchFile(entry, encoding: encoding) { (resultEntry, error) in
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
        }
    }
    
    // MARK: Download Data
    
    /**
     현재 url의 FileLength를 구하는 메쏘드
     - 완료 핸들러로 FileLength를 반환
     - Parameters:
        - completion: `StreamZipFileLengthCompletion` 완료 핸들러
     */
    private func getFileLength(completion: @escaping StreamZipFileLengthCompletion) {
        switch self.connection {
        // FTP인 경우
        case .ftp: self.getFileLengthFromFTP(completion: completion)
            
        // 그 외의 경우
        default:
            // 미지원 연결 방식 에러 반환
            return completion(0, StreamZip.Error.unsupportedConnection)
        }
    }
    /**
     FTP로 현재 url의 FileLength를 구하는 메쏘드
     - 완료 핸들러로 FileLength를 반환
     - Parameters:
        - completion: `StreamZipFileLengthCompletion` 완료 핸들러
     */
    private func getFileLengthFromFTP(completion: @escaping StreamZipFileLengthCompletion) {
        guard let ftpProvider = self.ftpProvider,
              let subPath = self.subPath else {
            return completion(0, StreamZip.Error.unknown)
        }
        let parentPath = (subPath as NSString).deletingLastPathComponent
        // progress 지정
        self.progress = ftpProvider.contentsOfDirectoryWithProgress(path: parentPath, completionHandler: { (ftpItems, error) in
            // 에러 발생시 중지
            if let error = error {
                print("StreamZipArchive>getFileLengthFromFTP(completion:): error 발생 = \(error.localizedDescription)")
                return completion(0, error)
            }
            /// 양측단의 슬래쉬(/)를 제거한 경로명끼리 비교
            let trimmedSubPath = subPath.trimmedSlash()
            let founds = ftpItems.filter { $0.path.trimmedSlash() == trimmedSubPath }
            guard let foundItem = founds.first else {
                print("StreamZipArchive>getFileLengthFromFTP(completion:): \(subPath) >> contents 미발견")
                return completion(0, StreamZip.Error.contentsIsEmpty)
            }
            return completion(UInt(foundItem.size), nil)
        })
    }

    /**
     현재 url의 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     */
    private func request(range: Range<UInt>, completion: @escaping StreamZipDataRequestCompletion) {
        switch self.connection {
        // FTP인 경우
        case .ftp: self.requestFromFTP(range: range, completion: completion)
            
        // 그 외의 경우
        default:
            // 미지원 연결 방식 에러 반환
            return completion(nil, StreamZip.Error.unsupportedConnection)
        }
    }
    /**
     FTP로 현재 url의 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     */
    private func requestFromFTP(range: Range<UInt>, completion: @escaping StreamZipDataRequestCompletion) {
        guard let ftpProvider = self.ftpProvider,
              let subPath = self.subPath else {
            return completion(nil, StreamZip.Error.unknown)
        }

        self.progress = ftpProvider.contents(path: subPath,
                                             offset: Int64(range.lowerBound),
                                             length: range.count) { (data, error) in
            if let error = error {
                print("StreamZipArchive>requestFromFTP(range:completion:): error 발생 = \(error.localizedDescription)")
                return completion(nil, error)
            }
            guard let data = data else {
                print("StreamZipArchive>requestFromFTP(range:completion:): data가 없음")
                return completion(nil, StreamZip.Error.contentsIsEmpty)
            }
            
            return completion(data, nil)
        }
    }
}

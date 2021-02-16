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
    
    /// Stream Zip Entry 배열
    public lazy var entries = [StreamZipEntry]()
    
    /// SyncQueue
    private let syncQueue = DispatchQueue(label: "djhan.StreamZipArchiver", attributes: .concurrent)

    // MARK: FTP Properties
    /// FTP File Provider
    weak var ftpProvider: FTPFileProvider?
    /// 실제 파일이 속한 상위폴더의 경로
    var mainPath: String?
    
    /// mainPath의 컨텐츠 목록
    private var contentsOfDirectory: [ContentOfDirectory]?
    
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
     */
    public init?(ftpProvider: FTPFileProvider) {
        guard let url = ftpProvider.baseURL else { return nil }
        self.ftpProvider = ftpProvider
        self.url = url
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
     특정 경로의 zip 파일에 접근, Entries 배열 생성
     - Parameters:
        - path: 파일 경로 지정
        - encoding: `String.Encoding` 형으로 파일명 인코딩 지정
        - completion: `StreamZipArchiveCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func fetchArchive(at path: String, encoding: String.Encoding, completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        
        // 기본 파일 길이를 0으로 리셋
        self.fileLength = 0
        
        // 파일 길이를 구해온다
        progress = self.getFileLength(at: path) { [weak self] (fileLength, error) in
            guard let strongSelf = self else {
                return completion(0, nil, error)
            }
            // 에러 발생시 종료 처리
            if let error = error {
                print("StreamZipArchive>fetchArchive(encoding:completion:): file length가 0")
                return completion(0, nil, error)
            }
            
            strongSelf.fileLength = fileLength
            
            // 파일 길이가 0인 경우 종료 처리
            guard strongSelf.fileLength > 0 else {
                return completion(0, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            if progress?.isCancelled == true {
                print("StreamZipArchive>fetchArchive(encoding:completion:): 작업 중지")
                return completion(0, nil, StreamZip.Error.aborted)
            }
                
            // Central Directory 정보를 찾고 entry 배열 생성
            if let subProgress = strongSelf.makeEntries(at: path, encoding: encoding, completion: completion) {
                // 하위 progress로 추가
                progress?.addChild(subProgress, withPendingUnitCount: 1)
            }
        }
        return progress
    }
    
    /**
     Central Directory 정보를 찾아 Entry 배열을 생성하는 내부 메쏘드
     - Parameters:
        - path: 파일 경로 지정
        - encoding: `String.Encoding`
        - completion: `StreamZipArchiveCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func makeEntries(at path: String, encoding: String.Encoding, completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        // 파일 길이가 0인 경우 종료 처리
        guard self.fileLength > 0 else {
            print("StreamZipArchive>makeEntries(_:completion:): file length가 0")
            completion(0, nil, StreamZip.Error.contentsIsEmpty)
            return nil
        }
        
        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = self.fileLength - 4096 ..< self.fileLength
        
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
                    
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                print("StreamZipArchive>makeEntries(_:completion:): 이미지 파일이 없음")
                return completion(0, nil, StreamZip.Error.aborted)
            }

            // Central Directory data 를 가져온다
            let subProgress = strongSelf.request(at: path, range: centralDirectoryRange) { [weak self] (data, error) in
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
        - entry: 압축 해제를 하고자 하는 `StreamZipEntry`
        - encoding: `String.Encoding`
        - completion: `StreamZipFileCompletion`
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func fetchFile(at path: String, entry: StreamZipEntry, encoding: String.Encoding, completion: @escaping StreamZipFileCompletion) -> Progress? {
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
                return completion(entry, nil)

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
     - 인코딩된 파일명 순서로 정렬, 그 중에서 최초의 이미지 파일을 반환한디
     - Parameters:
        - path: 파일 경로 지정
        - encoding: 파일명 인코딩 지정
        - completion: `StreamZipImageRequestCompletion` 타입으로 이미지 및 에러 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func firstImage(at path: String, encoding: String.Encoding, completion: @escaping StreamZipImageRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        
        progress = self.fetchArchive(at: path, encoding: encoding) { [weak self] (fileLength, entries, error) in
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

            let subProgress = strongSelf.fetchFile(at: path, entry: entry, encoding: encoding) { (resultEntry, error) in
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
     - 최대 512 x 512 크기로 썸네일 생성, CGImage 타입으로 완료 핸들러로 반환한다
     
     - Parameters:
        - path: 파일 경로 지정
        - size: 최대 크기 지정
        - completion: `StreamZipThumbnailRequestCompletion` 타입. CGImage, filePath, error 를 반환한다.
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func thumbnail(at path: String, size: NSSize, completion: @escaping StreamZipThumbnailRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        
        print("StreamZipArchive>thumbnail(completion:): \(path) >> 썸네일 이미지를 가져온다")
        progress = self.firstImage(at: path, encoding: .utf8) { [weak self] (image, filePath, error) in
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
                let banner = strongSelf.url.pathExtension
                drawBanner(banner,
                           bannerHeightRatio: preference.bannerHeightRatio,
                           maximumSize: size,
                           inContext: cgcontext,
                           isActiveContext: false,
                           inCanvas: canvasFrame)
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
        switch self.connection {
        // FTP인 경우
        case .ftp: return self.getFileLengthFromFTP(at: path, completion: completion)
            
        // 그 외의 경우
        default:
            // 미지원 연결 방식 에러 반환
            completion(0, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }
    /**
     FTP로 현재 url의 FileLength를 구하는 메쏘드
     - 완료 핸들러로 FileLength를 반환
     - Parameters:
        - path: 파일 경로
        - completion: `StreamZipFileLengthCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func getFileLengthFromFTP(at path: String, completion: @escaping StreamZipFileLengthCompletion) -> Progress? {
        //-------------------------------------------------------------------------------------------------------//
        /// 작업 종료용 내부 메쏘드
        func complete(_ contentsOfDirectory: [ContentOfDirectory]) {
            // 이미 컨텐츠 목록이 있는 경우
            let filtered = contentsOfDirectory.filter { $0.path.trimmedSlash() == path.trimmedSlash() }
            guard let foundItem = filtered.first else {
                print("StreamZipArchive>getFileLengthFromFTP(completion:): \(path) >> contents 미발견")
                return completion(0, StreamZip.Error.contentsIsEmpty)
            }
            // 찾아낸 아이템의 크기 반환
            return completion(UInt(foundItem.size), nil)
        }
        //-------------------------------------------------------------------------------------------------------//

        // path의 parent 경로를 구한다
        let parentPath = (path as NSString).deletingLastPathComponent

        // mainPath가 parent 경로와 동일한 경우
        // 이미 contentsOfDirectory가 있는 경우
        if self.mainPath == parentPath,
           let contentsOfDirectory = self.contentsOfDirectory {
            // 종료 처리 진행
            complete(contentsOfDirectory)
            return nil
        }
 
        // parentPath를 지정
        self.mainPath = parentPath
        
        // 컨텐츠 목록 생성 실행
        print("StreamZipArchive>getFileLengthFromFTP(completion:): \(path) >> 디렉토리 목록을 가져온다")
        // progress 지정
        var progress: Progress?
        progress = self.makeContentsOfDirectory(at: self.mainPath!) { (success, error) in
            if success == false || error != nil {
                print("StreamZipArchive>getFileLengthFromFTP(completion:): \(path) >> 에러 발생...")
                return completion(0, error)
            }
            
            if let contentsOfDirectory = self.contentsOfDirectory {
                complete(contentsOfDirectory)
            }
            else {
                print("StreamZipArchive>getFileLengthFromFTP(completion:): \(path) >> 디렉토리 목록 작성 실패!")
                completion(0, StreamZip.Error.contentsIsEmpty)
            }
        }
        return progress
    }
    
    /**
     mainPath 대입 후, contents of directory 배열 생성
     - Parameters:
        - mainPath: 상위 경로
        - completion: 성공 여부 및 에러값을 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func makeContentsOfDirectory(at mainPath: String, completion: @escaping (_ success: Bool, _ error: Error?) -> Void) -> Progress? {
        switch self.connection {
        // FTP인 경우
        case .ftp:
            return setupContentsOfDirectoryInFTP(at: mainPath, isUpdate: false, completion: completion)

        // 그 외: 미지원으로 실패 처리
        default:
            completion(false, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }
    /**
     mainPath 대입 후, contents of directory 배열 업데이트
     - Parameters:
        - mainPath: 상위 경로
        - completion: 성공 여부 및 에러값을 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func updateContentsOfDirectory(at mainPath: String, completion: @escaping (_ success: Bool, _ error: Error?) -> Void) -> Progress? {
        switch self.connection {
        // FTP인 경우
        case .ftp:
            return setupContentsOfDirectoryInFTP(at: mainPath, isUpdate: true, completion: completion)

        // 그 외: 미지원으로 실패 처리
        default:
            completion(false, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }

    /**
     FTP에서 mainPath 대입 후, contents of directory 배열 생성
     - Parameters:
        - mainPath: 상위 경로
        - isUpdate: 업데이트 여부. true인 경우에는 기존의 contentsOfDirectory 를 제거하고 새로 생성한다
        - completion: 성공 여부 및 에러값을 완료 핸들러로 반환
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func setupContentsOfDirectoryInFTP(at mainPath: String, isUpdate: Bool, completion: @escaping (_ success: Bool, _ error: Error?) -> Void) -> Progress? {
        // mainPath가 주어진 mainPath와 다른 경우인지 확인
        if self.mainPath != mainPath {
            self.mainPath = mainPath
        }
        // 동일한 경우
        else {
            // 업데이트가 아닌 경우
            // contentsOfDirectory 가 이미 생성된 경우, 중지 처리
            if isUpdate == false,
               self.contentsOfDirectory != nil {
                // 성공 종료 처리
                completion(true, nil)
                return nil
            }
        }
 
        guard let ftpProvider = self.ftpProvider else {
            print("StreamZipArchive>setupContentsOfDirectoryInFTP(at:completion:): ftpProvider가 nil!")
            completion(false, StreamZip.Error.unknown)
            return nil
        }
 
        // 컨텐츠 목록 제거
        self.contentsOfDirectory = nil

        // 컨텐츠 목록 생성 실행
        print("StreamZipArchive>setupContentsOfDirectoryInFTP(at:completion:): \(mainPath) >> 디렉토리 목록을 가져온다")
        // progress 지정
        var progress: Progress?
        progress = ftpProvider.contentsOfDirectoryWithProgress(path: mainPath) { (ftpItems, error) in
            print("StreamZipArchive>setupContentsOfDirectoryInFTP(at:completion:): \(mainPath) >> 디렉토리 목록 작성 완료")
            // 에러 발생시 중지
            if let error = error {
                print("StreamZipArchive>setupContentsOfDirectoryInFTP(at:completion:): error 발생 = \(error.localizedDescription)")
                return completion(false, error)
            }
            
            // progress 작업 개수 1 증가
            progress?.totalUnitCount += 1
            
            // contents of directory 배열에 아이템 대입
            self.contentsOfDirectory = ftpItems.map({ (ftpItem) -> ContentOfDirectory in
                // ftpProvider는 디렉토리인 경우 사이즈를 -1로 반환하기 때문에, 0으로 맞춘다
                let size = ftpItem.size > 0 ? ftpItem.size : 0
                return ContentOfDirectory.init(path: ftpItem.path, isDirectory: ftpItem.isDirectory, size: UInt(size))
            })

            // progress 처리 개수 1 증가
            progress?.completedUnitCount += 1
            
            // 완료 처리
            return completion(true, nil)
        }
        return progress
    }

    /**
     현재 url의 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - path: 파일 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func request(at path: String, range: Range<UInt>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        switch self.connection {
        // FTP인 경우
        case .ftp: return self.requestFromFTP(at: path, range: range, completion: completion)
            
        // 그 외의 경우
        default:
            // 미지원 연결 방식 에러 반환
            completion(nil, StreamZip.Error.unsupportedConnection)
            return nil
        }
    }
    /**
     FTP로 현재 url의 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - path: 데이터를 가져올 경로
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     - Returns: Progress 반환. 실패시 nil 반환
     */
    private func requestFromFTP(at path: String, range: Range<UInt>, completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        guard let ftpProvider = self.ftpProvider else {
            completion(nil, StreamZip.Error.unknown)
            return nil
        }

        return ftpProvider.contents(path: path,
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


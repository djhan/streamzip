//
//  StreamZipDefaultArchiver.swift
//  DefaultStreamZip
//
//  Created by DJ.HAN on 9/29/23.
//

import Foundation
import Cocoa

import CommonLibrary
import Detector
import zlib

// MARK: - StreamZip Default File Archiver Class -
/**
 로컬 파일을 해제하는 용도의 가장 기본적인 Archiver 클래스
 */
public class StreamZipDefaultArchiver {
    
    // MARK: - Properties
    /// 파일 URL
    public var url: URL
    
    /// 진행상태
    /// - async 메쏘드 사용 시, 이 프로퍼티로 진행상태를 파악한다
    public var progress: Progress?
    /// LocalEntries 진행상태
    /// - 외부에 노출되지 않는 프로퍼티
    private var entriesProgerss: Progress?
    /// Request 진행상태
    /// - 외부에 노출되지 않는 프로퍼티
    private var requestProgerss: Progress?
    /// Fetch 진행상태
    /// - 외부에 노출되지 않는 프로퍼티
    private var fetchProgerss: Progress?

    // MARK: - Initialization
    /// 초기화
    /// - 반드시 FileURL로 지정
    public init?(url: URL) {
        guard url.isFileURL == true else {
            return nil
        }
        self.url = url
    }
    
    // MARK: - Methods
    
    /// Local URL에서 Central Directory 정보를 찾아 Entry 배열을 생성하는 private 비동기 메쏘드
    /// - Parameters:
    ///     - encoding: `String.Encoding`. 미지정시 자동 인코딩
    ///     - parentProgress: requestProgerss 를 child로 추가할 부모 `Progress`
    /// - Returns: `Progress` 는 프로퍼티로 지정하고, 여기선 Result 타입으로 Entry 배열 또는 에러 값을 반환한다
    private func makeEntriesFromLocal(encoding: String.Encoding? = nil,
                                      addProgressTo parentProgress: Progress) async -> Result<[StreamZipEntry], StreamZip.Error> {
        // 파일 크기를 구한다
        let fileLength = self.url.fileSize
        
        //----------------------------------------------------------------//
        /// 종료 처리 내부 메쏘드
        /// - fileHandle도 닫는다
        func finish(_ entries: [StreamZipEntry]?, _ error: StreamZip.Error?) -> Result<[StreamZipEntry], StreamZip.Error> {
            // scope 종료시
            defer {
                // 완료 처리
                if let entriesProgerss = self.entriesProgerss {
                    let addCount = entriesProgerss.totalUnitCount - entriesProgerss.completedUnitCount
                    self.entriesProgerss?.completedUnitCount += addCount
                }
            }
            
            if let error = error {
                // 에러 발생 시 실패 처리
                return .failure(error)
            }
            guard let entries = entries else {
                // 엔트리 배열이 없는 경우 실패 처리
                return .failure(.contentsIsEmpty)
            }
            // 성공 시
            return .success(entries)
        }
        //----------------------------------------------------------------//
        
        // 파일 길이가 0인 경우 종료 처리
        guard fileLength > 0 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> File 길이가 0. 중지.")
            return finish(nil, StreamZip.Error.contentsIsEmpty)
        }
        // 4096 바이트보다 짧은 경우도 종료 처리
        guard fileLength >= 4096 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> File 길이가 4096 바이트 미만. 중지.")
            // 빈 파일로 간주한다
            return finish(nil, StreamZip.Error.contentsIsEmpty)
        }
        
        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = fileLength - 4096 ..< fileLength
        
        self.entriesProgerss = nil
        self.entriesProgerss = Progress(totalUnitCount: 2)
        parentProgress.addChild(self.entriesProgerss!, withPendingUnitCount: 1)

        // 해당 범위에서 request 비동기 실행
        let requestResult = await self.request(range: range, addProgressTo: self.entriesProgerss!)
        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #1.")
            return finish(nil, StreamZip.Error.aborted)
        }
        // 에러 검증
        if case let .failure(error) = requestResult {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 마지막 4096 바이트 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            // 에러 발생 시, 그대로 반환 처리
            return finish(nil, error)
        }
        guard case let .success(data) = requestResult,
              data.count > 4 else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 에러가 없는데 데이터 크기가 4바이트 이하. End of Central Directory가 없는 것일 수 있음.")
            return finish(nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
        }
        // End of Central Directory 정보 레코드를 가져온다
        guard let zipEndRecord = ZipEndRecord.make(from: data, encoding: encoding) else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> end of central directory 구조체 초기화 실패. 중지.")
            return finish(nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
        }
        
        // Central Directory 시작 offset과 size을 가져온다
        let offsetOfCentralDirectory = UInt64(zipEndRecord.offsetOfStartOfCentralDirectory)
        let sizeOfCentralDirectory = UInt64(zipEndRecord.sizeOfCentralDirectory)
        let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory
        
        let subRequestResult = await self.request(range: centralDirectoryRange, addProgressTo: self.entriesProgerss!)
        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #2.")
            return finish(nil, StreamZip.Error.aborted)
        }
        if case let .failure(error) = subRequestResult {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> central directory data 전송중 에러 발생 = \(error.localizedDescription).")
            return finish(nil, error)
        }
        guard case let .success(data) = subRequestResult else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 에러가 없는데 central directory data 크기가 0.")
            return finish(nil, StreamZip.Error.centralDirectoryIsFailed)
        }
        
        guard let entries = StreamZipEntry.makeEntries(from: data, encoding: encoding) else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> Stream Zip Entries 생성에 실패.")
            return finish(nil, StreamZip.Error.centralDirectoryIsFailed)
        }
        // 엔트리 배열 반환, 종료 처리
        return finish(entries, nil)
    }
    /// Local URL에서 Central Directory 정보를 찾아 Entry 배열을 생성하는 private 메쏘드
    /// - Parameters:
    ///     - encoding: `String.Encoding`. 미지정시 자동 인코딩
    ///     - completion: `StreamZipArchiveCompletion`
    /// - Returns: Progress 반환. 실패시 nil 반환
    public func makeEntriesFromLocal(encoding: String.Encoding? = nil,
                                     completion: @escaping StreamZipArchiveCompletion) -> Progress? {
        // 파일 크기를 구한다
        let fileLength = self.url.fileSize
        
        //----------------------------------------------------------------//
        /// 종료 처리 내부 메쏘드
        /// - fileHandle도 닫는다
        func finish(_ entries: [StreamZipEntry]?, _ error: Error?) {
            completion(fileLength, entries, error)
        }
        //----------------------------------------------------------------//
        
        // 파일 길이가 0인 경우 종료 처리
        guard fileLength > 0 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> File 길이가 0. 중지.")
            finish(nil, StreamZip.Error.contentsIsEmpty)
            return nil
        }
        // 4096 바이트보다 짧은 경우도 종료 처리
        guard fileLength >= 4096 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> File 길이가 4096 바이트 미만. 중지.")
            // 빈 파일로 간주한다
            finish(nil, StreamZip.Error.contentsIsEmpty)
            return nil
        }
        
        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = fileLength - 4096 ..< fileLength
        
        var progress: Progress?
        progress = self.request(range: range) { [weak self] data, error in
            guard let strongSelf = self else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: Self가 NIL. 중지.")
                return finish(nil, error)
            }
            if let error = error {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> 마지막 4096 바이트 데이터 전송중 에러 발생 = \(error.localizedDescription).")
                return finish(nil, error)
            }
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(strongSelf.url.filePath) >> 사용자 중지 발생.")
                return finish(nil, StreamZip.Error.aborted)
            }
            
            guard let data = data,
                  data.count > 4 else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> 에러가 없는데 데이터 크기가 4바이트 이하. End of Central Directory가 없는 것일 수 있음.")
                return finish(nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // End of Central Directory 정보 레코드를 가져온다
            guard let zipEndRecord = ZipEndRecord.make(from: data, encoding: encoding) else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> end of central directory 구조체 초기화 실패. 중지.")
                return finish(nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // Central Directory 시작 offset과 size을 가져온다
            let offsetOfCentralDirectory = UInt64(zipEndRecord.offsetOfStartOfCentralDirectory)
            let sizeOfCentralDirectory = UInt64(zipEndRecord.sizeOfCentralDirectory)
            let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory
            
            // Central Directory data 를 가져온다
            let subProgress = strongSelf.request(range: centralDirectoryRange) { (data, error) in
                if let error = error {
                    EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> central directory data 전송중 에러 발생 = \(error.localizedDescription).")
                    return finish(nil, error)
                }
                guard let data = data else {
                    EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(strongSelf.url.filePath) >> 에러가 없는데 central directory data 크기가 0.")
                    return finish(nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                guard let entries = StreamZipEntry.makeEntries(from: data, encoding: encoding) else {
                    EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(strongSelf.url.filePath) >> Stream Zip Entries 생성에 실패.")
                    return finish(nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                // 완료 처리
                return finish(entries, nil)
            }
            if subProgress != nil {
                // Progress 전체 개수 증가
                progress?.totalUnitCount += 1
                progress?.addChild(subProgress!, withPendingUnitCount: 1)
            }
        }
        
        return progress
    }
    
    /// 로컬 영역의 특정 범위 데이터를 가져오는 비동기 메쏘드
    /// - Important: `fileHandle` 패러미터의 close 처리는 이 메쏘드를 부른 곳에서 처리해야 한다
    /// - Parameters:
    ///     - range: 데이터를 가져올 범위
    ///     - parentProgress: requestProgerss 를 child로 추가할 부모 Progress
    /// - Returns: Progress 는 프로퍼티로 지정하며, 여기선 Result 타입으로 데이터 또는 에러를 반환한다.
    private func request(range: Range<UInt64>,
                         addProgressTo parentProgress: Progress) async -> Result<Data, StreamZip.Error> {
        guard Task.isCancelled == false else {
            // 사용자 중지 시 에러 처리
            return .failure(StreamZip.Error.aborted)
        }
            
        self.requestProgerss = nil
        self.requestProgerss = Progress.init(totalUnitCount: 1)
        // requestProgress를 새끼 Progress로 추가한다
        parentProgress.addChild(self.requestProgerss!, withPendingUnitCount: 1)
        
        // scope 종료시
        defer {
            self.requestProgerss?.completedUnitCount += 1
        }
        
        do {
            let fileHandle = try FileHandle.init(forReadingFrom: self.url)
            
            // scope 종료시
            defer {
                // 15.4 이상인 경우
                if #available(macOS 10.15.4, *) {
                    try? fileHandle.close()
                }
                // 이하인 경우
                else {
                    fileHandle.closeFile()
                }
            }
            
            try fileHandle.seek(toOffset: range.lowerBound)
            let count = Int(range.upperBound - range.lowerBound)
            var data: Data?
            // 15.4 이상인 경우
            if #available(macOS 10.15.4, *) {
                data = try fileHandle.read(upToCount: count)
            }
            // 이하인 경우
            else {
                data = fileHandle.readData(ofLength: count)
            }
            
            guard let data = data else {
                // 빈 데이터 에러 반환
                return .failure(StreamZip.Error.contentsIsEmpty)
            }
            return .success(data)
        }
        catch {
            // 알 수 없는 에러로 중단
            return .failure(StreamZip.Error.unknown)
        }
    }
    /// 로컬 영역의 특정 범위 데이터를 가져오는 메쏘드
    /// - Important: `fileHandle` 패러미터의 close 처리는 이 메쏘드를 부른 곳에서 처리해야 한다
    /// - Parameters:
    ///     - range: 데이터를 가져올 범위
    ///     - completion: `StreamZipDataRequestCompletion` 완료 핸들러
    /// - Returns: Progress 반환. 실패시 nil 반환
    private func request(range: Range<UInt64>,
                         completion: @escaping StreamZipDataRequestCompletion) -> Progress? {
        let progress = Progress.init(totalUnitCount: 1)
        // userInitiated 로 백그라운드 작업 개시
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in

            // scope 종료시
            defer {
                progress.completedUnitCount += 1
            }
            
            guard let strongSelf = self else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: self 가 NIL.")
                // 알 수 없는 에러로 중단
                completion(nil, StreamZip.Error.unknown)
                return
            }

            do {
                let fileHandle = try FileHandle.init(forReadingFrom: strongSelf.url)
                
                // scope 종료시
                defer {
                    // 15.4 이상인 경우
                    if #available(macOS 10.15.4, *) {
                        try? fileHandle.close()
                    }
                    // 이하인 경우
                    else {
                        fileHandle.closeFile()
                    }
                }
                
                try fileHandle.seek(toOffset: range.lowerBound)
                let count = Int(range.upperBound - range.lowerBound)
                var data: Data?
                // 15.4 이상인 경우
                if #available(macOS 10.15.4, *) {
                    data = try fileHandle.read(upToCount: count)
                }
                // 이하인 경우
                else {
                    data = fileHandle.readData(ofLength: count)
                }
                
                guard let data = data else {
                    // 빈 데이터 에러 반환
                    completion(nil, StreamZip.Error.contentsIsEmpty)
                    return
                }
                // 데이터 반환 처리
                completion(data, nil)
            }
            catch {
                // 알 수 없는 에러로 중단
                completion(nil, StreamZip.Error.unknown)
                return
            }
        }
        // progress 반환
        return progress
    }
    
    // MARK: Process Entry Data
    /// Entry 데이터 처리 및 완료 처리 비동기 메쏘드
    /// - Parameters:
    ///     - entry: 데이터를 가져온 `StreamZipEntry`
    ///     - encoding:`String.Encoding`
    ///     - data: 가져온 Entry 데이터. 옵셔널
    ///     - error: 에러값. 옵셔널
    /// - Returns: Result 타입으로 StreamZipEntry 또는 에러 값을 반환한다
    private func processEntryData(at entry: StreamZipEntry,
                                  encoding: String.Encoding? = nil,
                                  data: Data?,
                                  error: Error?) async -> Result<StreamZipEntry, Error> {
        if let error = error {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            return .failure(error)
        }
        guard let data = data else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: 에러가 없는데 데이터 크기가 0. 중지.")
            return .failure(StreamZip.Error.contentsIsEmpty)
        }
        
        // Local Zip File Header 구조체 생성
        guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: local file hedaer를 찾지 못함. 중지.")
            return .failure(StreamZip.Error.localFileHeaderIsFailed)
        }
        
        let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)
        
        switch entry.method {
            // Defalte 방식인 경우
        case Z_DEFLATED:
            do {
                // 성공 처리
                let decompressData = try data.unzip(offset: offset,
                                                    compressedSize: entry.sizeCompressed,
                                                    crc32: entry.crc32)
                entry.data = decompressData
                return .success(entry)
            }
            catch {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 해제 도중 에러 발생 = \(error.localizedDescription).")
                return .failure(error)
            }
            
            // 비압축시
        case 0:
            // upperBound가 현재 데이터 길이를 초과하지 않도록 조절한다
            // 이상하지만, uncompressedSize를 더한 값이 데이터 길이를 초과하는 경우가 있다
            // 아마도 잘못 만들어진 zip 파일인 것으로 추정된다
            let upperBound = offset + entry.sizeUncompressed > data.count ? data.count : offset + entry.sizeUncompressed
            entry.data = data[offset ..< upperBound]
            return .success(entry)
            
            // 그 외의 경우
        default:
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 미지원 압축 해제 방식. 데이터 해제 불가.")
            return .failure(StreamZip.Error.unsupportedCompressMethod)
        }
    }
    /// Entry 데이터 처리 및 완료 처리
    /// - Parameters:
    ///     - entry: 데이터를 가져온 `StreamZipEntry`
    ///     - encoding:`String.Encoding`
    ///     - data: 가져온 Entry 데이터. 옵셔널
    ///     - error: 에러값. 옵셔널
    ///     - completion: `StreamZipFileCompletion` 완료 핸들러
    private func processEntryData(at entry: StreamZipEntry,
                                  encoding: String.Encoding? = nil,
                                  data: Data?,
                                  error: Error?,
                                  completion: StreamZipFileCompletion) {
        if let error = error {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            return completion(entry, error)
        }
        guard let data = data else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: 에러가 없는데 데이터 크기가 0. 중지.")
            return completion(entry, StreamZip.Error.contentsIsEmpty)
        }
        
        // Local Zip File Header 구조체 생성
        guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: local file hedaer를 찾지 못함. 중지.")
            return completion(entry, StreamZip.Error.localFileHeaderIsFailed)
        }
        
        let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)
        
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
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 해제 도중 에러 발생 = \(error.localizedDescription).")
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
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 미지원 압축 해제 방식. 데이터 해제 불가.")
            return completion(entry, StreamZip.Error.unsupportedCompressMethod)
        }
    }
    // MARK: Get Data from Entry
    /// 특정 Entry의 파일 다운로드 및 압축 해제 비동기 메소드
    ///  - 다운로드후 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
    /// - Parameters:
    ///    - entry: 압축 해제를 하고자 하는 `StreamZipEntry`
    ///    - encoding: `String.Encoding`. 미지정시 자동 인코딩
    ///    - parentProgress: requestProgerss 를 child로 추가할 부모 Progress
    ///    - checkSafety: 안전성 확인 여부, False 지정시 offset + compressedSize 의 길이 초과 여부, CRC 정합성 여부를 모두 무시한다.
    ///    예전에 만들어진 zip파일이 이 정합성 검사를 통과 못하는 관계로 퀵룩 썸네일 생성 시에는 이 값을 false로 지정한다. 기본값은 true.
    /// - Returns: `Result` 타입으로 `StreamZipEntry` 또는 에러 반환
    private func fetchFile(entry: StreamZipEntry,
                           encoding: String.Encoding? = nil,
                           addProgressTo parentProgress: Progress,
                           checkSafety: Bool = true) async -> Result<StreamZipEntry, StreamZip.Error> {
        
        //-----------------------------------------------------------------------------------------------------------//
        /// 종료 처리 내부 메쏘드
        func finish(_ error: StreamZip.Error? = nil) -> Result<StreamZipEntry, StreamZip.Error> {
            defer {
                self.fetchProgerss?.completedUnitCount = 2
            }
            
            guard let error = error else {
                // 에러가 없으면 성공으로 간주하고 entry 반환
                return .success(entry)
            }
            // 실패 처리
            return .failure(error)
        }
        //-----------------------------------------------------------------------------------------------------------//

        self.fetchProgerss = nil
        self.fetchProgerss = Progress(totalUnitCount: 2)
        // fetchProgerss를 새끼 Progress로 추가한다
        parentProgress.addChild(self.fetchProgerss!, withPendingUnitCount: 1)

        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #1.")
            return finish(.aborted)
        }

        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
        
        let lowerBound = UInt64(entry.offset)
        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt64(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let uppderbound = lowerBound + length > self.url.fileSize ? self.url.fileSize : lowerBound + length
        // 다운로드 범위를 구한다
        let range = lowerBound ..< uppderbound
        
        // 해당 범위의 데이터를 받아온다
        let requestResult = await self.request(range: range, addProgressTo: self.entriesProgerss!)
                
        // 에러 검증
        if case let .failure(error) = requestResult {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            // 에러 발생 시, 그대로 반환 처리
            return finish(error)
        }
        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #2.")
            return finish(.aborted)
        }
        guard case let .success(data) = requestResult,
              data.count > 0 else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 에러가 없는데 데이터 크기가 0.")
            return finish(.contentsIsEmpty)
        }
        // Local Zip File Header 구조체 생성
        guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> local file hedaer를 찾지 못함.")
            return finish(.localFileHeaderIsFailed)
        }
        
        let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)
        
        switch entry.method {
            // Defalte 방식인 경우
        case Z_DEFLATED:
            do {
                // 성공 처리
                let decompressData = try data.unzip(offset: offset,
                                                    compressedSize: entry.sizeCompressed,
                                                    crc32: entry.crc32,
                                                    checkSafety: checkSafety)
                entry.data = decompressData
                // 성공 반환
                return finish()
            }
            catch {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 해제 도중 에러 발생 = \(error.localizedDescription).")
                return finish(.deflationIsFailed)
            }
            
            // 비압축시
        case 0:
            // upperBound가 현재 데이터 길이를 초과하지 않도록 조절한다
            // 이상하지만, uncompressedSize를 더한 값이 데이터 길이를 초과하는 경우가 있다
            // 아마도 잘못 만들어진 zip 파일인 것으로 추정된다
            let upperBound = offset + entry.sizeUncompressed > data.count ? data.count : offset + entry.sizeUncompressed
            entry.data = data[offset ..< upperBound]
            // 성공 반환
            return finish()
            
            // 그 외의 경우
        default:
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >>미지원 압축 해제 방식. 데이터 해제 불가.")
            return finish(.unsupportedCompressMethod)
        }
    }
    /// 특정 Entry의 파일 다운로드 및 압축 해제 메쏘드
    ///  - 다운로드후 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
    /// - Parameters:
    ///    - entry: 압축 해제를 하고자 하는 `StreamZipEntry`
    ///    - encoding: `String.Encoding`. 미지정시 자동 인코딩
    ///    - checkSafety: 안전성 확인 여부, False 지정시 offset + compressedSize 의 길이 초과 여부, CRC 정합성 여부를 모두 무시한다. 기본값은 true.
    ///    - completion: `StreamZipFileCompletion`
    /// - Returns: Progress 반환. 실패시 nil 반환
    public func fetchFile(entry: StreamZipEntry,
                          encoding: String.Encoding? = nil,
                          checkSafety: Bool = true,
                          completion: @escaping StreamZipFileCompletion) -> Progress? {
        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
        
        let lowerBound = UInt64(entry.offset)
        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt64(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let uppderbound = lowerBound + length > self.url.fileSize ? self.url.fileSize : lowerBound + length
        // 다운로드 범위를 구한다
        let range = lowerBound ..< uppderbound
        // 해당 범위의 데이터를 받아온다
        return self.request(range: range) { [weak self] (data, error) in
            guard let strongSelf = self else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: Self 가 NIL.")
                return completion(entry, StreamZip.Error.unknown)
            }
            
            if let error = error {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
                return completion(entry, error)
            }
            guard let data = data else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> 에러가 없는데 데이터 크기가 0.")
                return completion(entry, StreamZip.Error.contentsIsEmpty)
            }
            
            // Local Zip File Header 구조체 생성
            guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> local file hedaer를 찾지 못함.")
                return completion(entry, StreamZip.Error.localFileHeaderIsFailed)
            }
            
            let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)
            
            switch entry.method {
                // Defalte 방식인 경우
            case Z_DEFLATED:
                do {
                    // 성공 처리
                    let decompressData = try data.unzip(offset: offset,
                                                        compressedSize: entry.sizeCompressed,
                                                        crc32: entry.crc32,
                                                        checkSafety: checkSafety)
                    entry.data = decompressData
                    return completion(entry, nil)
                }
                catch {
                    EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(strongSelf.url.filePath) >> 해제 도중 에러 발생 = \(error.localizedDescription).")
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
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(strongSelf.url.filePath) >>미지원 압축 해제 방식. 데이터 해제 불가.")
                return completion(entry, StreamZip.Error.unsupportedCompressMethod)
            }
        }
    }
    
    // MARK: - Image

    // MARK: Public Async Method for Image
    /// 아카이브 중 최초 이미지를 반환하는 비동기 메쏘드
    /// - 인코딩된 파일명 순서로 정렬, 그 중에서 최초의 이미지 파일을 반환한디
    /// - Parameters:
    ///     - encoding: 파일명 인코딩 지정. 미지정시 자동 인코딩
    ///     - checkSafety: 안전성 확인 여부, False 지정시 offset + compressedSize 의 길이 초과 여부, CRC 정합성 여부를 모두 무시한다.
    ///     예전에 만들어진 zip파일이 이 정합성 검사를 통과 못하는 관계로 퀵룩 썸네일 생성 시에는 이 값을 false로 지정한다. 기본값은 true
    /// - Returns: Result 타입으로 NSImage 또는 에러 반환
    public func firstImage(encoding: String.Encoding? = nil,
                           checkSafety: Bool = true) async -> Result<NSImage, StreamZip.Error> {
        let result = await imageWithTitleDicts(count: 1)
        switch result {
            // 성공시
        case .success(let dicts):
            guard let image = dicts.first?["image"] as? NSImage else {
                return .failure(.contentsIsEmpty)
            }
            return .success(image)
            
            // 에러는 그대로 반환
        case .failure(let error): return .failure(error)
        }
        /*
        //-----------------------------------------------------------------------------------------------------------//
        /// 종료 처리 내부 메쏘드
        func finish(image: NSImage? = nil, error: StreamZip.Error? = nil) -> Result<NSImage, StreamZip.Error> {
            
            defer {
                self.progress?.completedUnitCount = 2
            }
            
            if let error = error {
                // 에러 발생 시 즉시 에러 반환
                return .failure(error)
            }
            guard let image = image else {
                // 빈 이미지 에러 반환
                return .failure(.contentsIsEmpty)
            }
            // 이미지 반환
            return .success(image)
        }
        //-----------------------------------------------------------------------------------------------------------//

        self.progress = nil
        self.progress = Progress(totalUnitCount: 2)
        
        let makeEntriesResult = await self.makeEntriesFromLocal(encoding: encoding, addProgressTo: self.progress!)
        
        // 에러 검증
        if case let .failure(error) = makeEntriesResult {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            // 에러 발생 시, 그대로 반환 처리
            return finish(error: error)
        }
        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #1.")
            return finish(error: .aborted)
        }
        guard case var .success(entries) = makeEntriesResult else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> entry가 0개")
            return finish(error: .contentsIsEmpty)
        }

        // entry를 이름순으로 정렬
        entries.sort { $0.filePath < $1.filePath }
        
        var count = 0
        
        for entry in entries {
            guard let utiString = entry.filePath.utiString else {
                continue
            }
            if Detector.shared.detectImageFormat(utiString) == .unknown {
                continue
            }
            
            let fetchResult = await self.fetchFile(entry: entry, addProgressTo: self.progress!, checkSafety: checkSafety)

            // 작업 중지시 중지 처리
            if Task.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #2.")
                return finish(error: .aborted)
            }

            // 에러 검증
            if case let .failure(error) = fetchResult {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
                // 에러 발생 시, 그대로 반환 처리
                return finish(error: error)
            }
            // 작업 중지시 중지 처리
            if Task.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생.")
                return finish(error: .aborted)
            }
            guard case .success(_) = fetchResult,
                  let data = entry.data,
                  let image = NSImage.init(data: data) else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: data가 nil, 또는 image가 아님.")
                guard count > 10 else {
                    // 잘못된 이미지인 경우 최대 10장까지 건너뛰며 시도한다
                    count += 1
                    continue
                }
                return finish(error: StreamZip.Error.contentsIsEmpty)
            }
            
            return .success(image)
        }
        
        EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: image가 없음.")
        return finish(error: StreamZip.Error.contentsIsEmpty)
         */
    }
    /// 아카이브 중 최초 이미지를 CGImage로 반환하는 비동기 메쏘드
    /// - 인코딩된 파일명 순서로 정렬, 그 중에서 최초의 이미지 파일을 반환한디
    /// - Parameters:
    ///     - encoding: 파일명 인코딩 지정. 미지정시 자동 인코딩
    ///     - checkSafety: 안전성 확인 여부, False 지정시 offset + compressedSize 의 길이 초과 여부, CRC 정합성 여부를 모두 무시한다.
    ///     예전에 만들어진 zip파일이 이 정합성 검사를 통과 못하는 관계로 퀵룩 썸네일 생성 시에는 이 값을 false로 지정한다. 기본값은 true
    /// - Returns: Result 타입으로 CGImage 또는 에러 반환
    public func firstCGImage(encoding: String.Encoding? = nil,
                             checkSafety: Bool = true) async -> Result<CGImage, StreamZip.Error> {
        let result = await self.firstImage(encoding: encoding, checkSafety: checkSafety)
        // 에러 검증
        if case let .failure(error) = result {
            // 에러 발생 시, 그대로 반환 처리
            return .failure(error)
        }
        guard case let .success(image) = result,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // 이미지가 없음
            return .failure(.contentsIsEmpty)
        }
        // 성공 시
        return .success(cgImage)
    }
    
    /// 지정된 갯수 만큼의 이미지 + 타이틀 딕셔너리 배열 반환 비동기 메쏘드
    /// - Returns: Result 타입으로 이미지 + 타이틀 딕셔너리 배열 또는 에러 반환.
    public func imageWithTitleDicts(count: Int = 10,
                                    encoding: String.Encoding? = nil) async -> Result<[Dictionary<String, Any>], StreamZip.Error> {
        
        self.progress = nil
        self.progress = Progress(totalUnitCount: 2)

        //-----------------------------------------------------------------------------------------------------------//
        /// 종료 처리 내부 메쏘드
        func finish(dicts: [Dictionary<String, Any>]? = nil, 
                    error: StreamZip.Error? = nil) -> Result<[Dictionary<String, Any>], StreamZip.Error> {
            
            defer {
                let addCount = (self.progress?.totalUnitCount ?? 0) - (self.progress?.completedUnitCount ?? 0)
                self.progress?.completedUnitCount += addCount
            }
            
            if let error = error {
                // 에러 발생 시 즉시 에러 반환
                return .failure(error)
            }
            guard let dicts = dicts else {
                // 빈 이미지 에러 반환
                return .failure(.contentsIsEmpty)
            }
            // 이미지 반환
            return .success(dicts)
        }
        //-----------------------------------------------------------------------------------------------------------//
        
        let makeEntriesResult = await self.makeEntriesFromLocal(encoding: encoding, addProgressTo: self.progress!)
        
        // 에러 검증
        if case let .failure(error) = makeEntriesResult {
            EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
            // 에러 발생 시, 그대로 반환 처리
            return finish(error: error)
        }
        // 작업 중지시 중지 처리
        if Task.isCancelled == true {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #1.")
            return finish(error: .aborted)
        }
        guard case var .success(entries) = makeEntriesResult,
              entries.count > 0 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> entry가 0개")
            return finish(error: .contentsIsEmpty)
        }

        // entry를 이름순으로 정렬
        entries.sort { $0.filePath < $1.filePath }
        
        // 하위 Progress를 지정 생성 개수로 지정, Progress에 추가
        let subProgress = Progress.init(totalUnitCount: Int64(count))
        self.progress?.addChild(subProgress, withPendingUnitCount: 1)

        // 타이틀 / 이미지 딕셔너리
        var dicts = [Dictionary<String, Any>]()
        
        for entry in entries {
            guard let utiString = entry.filePath.utiString else {
                continue
            }
            if Detector.shared.detectImageFormat(utiString) == .unknown {
                continue
            }
            
            let fetchResult = await self.fetchFile(entry: entry, addProgressTo: self.progress!)

            // 작업 중지시 중지 처리
            if Task.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생 #2.")
                return finish(error: .aborted)
            }

            // 에러 검증
            if case let .failure(error) = fetchResult {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(self.url.filePath) >> 데이터 전송중 에러 발생 = \(error.localizedDescription).")
                // 에러 발생 시, 그대로 반환 처리
                return finish(error: error)
            }
            // 작업 중지시 중지 처리
            if Task.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(self.url.filePath) >> 사용자 중지 발생.")
                return finish(error: .aborted)
            }
            guard case .success(_) = fetchResult,
                  let data = entry.data,
                  let image = NSImage.init(data: data) else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: data가 nil, 또는 image가 아님.")
                // 잘못된 이미지인 경우 다음 이미지로 건너뛴다
                continue
            }

            let dict: [String : Any] = ["title": entry.filePath.lastPathComponent,
                                        "image": image as Any]
            dicts.append(dict)
            // 하위 Progress 완료 1 추가
            subProgress.completedUnitCount += 1
            // 지정 개수 초과 시 중지
            if subProgress.completedUnitCount >= count {
                break
            }
        }

        // 지정 개수보다 모자라게 처리된 경우, 확인해서 완료 처리
        let addCount = subProgress.totalUnitCount - subProgress.completedUnitCount
        subProgress.completedUnitCount += addCount

        guard dicts.count > 0 else {
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: image가 없음.")
            return finish(error: StreamZip.Error.contentsIsEmpty)
        }
        
        // 성공 처리
        return finish(dicts: dicts)
    }

    // MARK: Completion Handler Method for Image
    /// 아카이브 중 최초 이미지를 반환하는 메쏘드
    /// - 인코딩된 파일명 순서로 정렬, 그 중에서 최초의 이미지 파일을 반환한디
    /// - Parameters:
    ///     - encoding: 파일명 인코딩 지정. 미지정시 자동 인코딩
    ///     - completion: `StreamZipImageRequestCompletion` 타입으로 이미지 및 에러 반환
    /// - Returns: Progress 반환. 실패시 nil 반환
    public func firstImage(encoding: String.Encoding? = nil,
                           completion: @escaping StreamZipImageRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: 첫 번째 이미지를 가져오기 위한 시도.")
        progress = self.makeEntriesFromLocal(encoding: encoding) { [weak self] (fileLength, entries, error) in
            guard let strongSelf = self else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: self가 nil. 중지")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            // 에러 발생시
            if let error = error {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 에러 발생 = \(error.localizedDescription)")
                return completion(nil, nil, error)
            }
            guard var entries = entries else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: entry가 0개")
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
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: 이미지 파일이 없음")
                return completion(nil, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: 작업 취소 처리.")
                return completion(nil, nil, StreamZip.Error.aborted)
            }
            
            let subProgress = strongSelf.fetchFile(entry: entry, encoding: encoding) { (resultEntry, error) in
                // 에러 발생시
                if let error = error {
                    EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: 전송 중 에러 발생 = \(error.localizedDescription)")
                    return completion(nil, nil, error)
                }
                guard let data = resultEntry.data,
                      let image = NSImage.init(data: data) else {
                    EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: data가 nil, 또는 image가 아님.")
                    return completion(nil, nil, StreamZip.Error.contentsIsEmpty)
                }
                
                return completion(image, resultEntry.filePath, nil)
            }
            if subProgress != nil {
                // Progress 전체 개수 증가
                progress?.totalUnitCount += 1
                progress?.addChild(subProgress!, withPendingUnitCount: 1)
            }
        }
        
        return progress
    }
    
    // 현재 미사용
    /*
    /**
     압축 파일 썸네일 이미지 반환
     - 그룹 환경설정에서 배너 표시가 지정된 경우 배너까지 추가
     - 지정된 크기로 썸네일 생성, CGImage 타입으로 완료 핸들러로 반환한다
     
     - Parameters:
         - size: 최대 크기 지정
         - completion: `StreamZipThumbnailRequestCompletion` 타입. CGImage, filePath, error 를 반환한다.
     - Returns: Progress 반환. 실패시 nil 반환
     */
    public func thumbnail(size: NSSize,
                          completion: @escaping StreamZipThumbnailRequestCompletion) -> Progress? {
        // Progress 선언
        var progress: Progress?
        
        let title = self.url.lastPathComponent
        
        EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(title) >> 썸네일 이미지 획득 시도.")
        progress = self.firstImage(encoding: nil) { [weak self] (image, filePath, error) in
            guard let strongSelf = self else {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(title) >> SELF가 NIL.")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            // 에러 발생시
            if let error = error {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(title) >> 에러 발생 = \(error.localizedDescription).")
                return completion(nil, nil, error)
            }
            
            EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(title) >> 드로잉 개시.")
            
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
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(title) >> cgimage로 변환하는데 실패한 것으로 추정.")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            
            guard let cgcontext = strongSelf.offscreenCGContext(with: targetFrameRects.canvasFrame.size, buffer: nil) else {
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(title) >> cgcontext 생성에 실패.")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            
            let canvasFrame = targetFrameRects.canvasFrame
            let targetFrame = targetFrameRects.targetFrame
            
            // 배경을 흰색으로 채운다
            cgcontext.setFillColor(NSColor.white.cgColor)
            cgcontext.fill(canvasFrame)
            
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(title) >> 작업 취소 처리 (1).")
                return completion(nil, nil, StreamZip.Error.aborted)
            }
            
            // 이미지를 드로잉
            cgcontext.draw(cgImage, in: targetFrame)
            // 배너 필요시 드로잉
            if preference.showExtensionBanner == true {
                //let banner = (path as NSString).pathExtension
                let banner = title.pathExtension()
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
                EdgeLogger.shared.archiveLogger.log(level: .error, "\(#function) :: \(title) >> cgImage 생성에 실패.")
                return completion(nil, nil, StreamZip.Error.unknown)
            }
            
            // 작업 중지시 중지 처리
            if progress?.isCancelled == true {
                EdgeLogger.shared.archiveLogger.log(level: .debug, "\(#function) :: \(title) >> 작업 취소 처리 (2).")
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
     */
}

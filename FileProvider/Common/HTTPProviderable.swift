//
//  HTTPProviderable.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

import CommonLibrary

// MARK: - HTTP Providerable Protocol -
/// HTTP 파일 공급자 프로토콜
internal protocol HTTPProviderable: FileProviderable {
    
    // MARK: - Properties
    /// URL Credential
    var credential: URLCredential { get set }
    
    /// Session Delegate
    var sessionDelegate: SessionDelegate<Self>? { get set }
    /// URLSession
    var _session: URLSession! { get set }

    /// URL Session Queue
    var operationQueue: OperationQueue { get set }

    /// E-Tag 또는 Revision identifier로 Cache Validating
    var validatingCache: Bool { get set }
    
    /// 최대 업로드 사이즈
    var maxUploadSize: Int64 { get }

    /// 접근 가능 여부
    func canAccessible() async -> Result<Bool, Error>

    // MARK: - Methods
    
    /// 특정 경로의 아이템을 찾아서 반환
    /// - Important: 실제 `Data`가 아니라, 정보만 격납된 아이템만 반환한다.
    /// - Parameter path: 상대 경로.
    /// - Returns: `FileItem` 또는 에러 반환.
    func item(of path: String) async -> Result<FileItem, Error>
        
    /// 특정 상대 경로에 독립적으로 접근하기 위한 URL을 가져온다
    /// - OneDrive / WebDAV 여부에 따라 다른 로직을 실행한다.
    /// - Parameter path: 접근하려는 상대적 경로 지정.
    /// - Returns: `URL` 반환
    func url(of path: String) -> URL
    /// 특정 URL의 상대적 경로 반환
    /// - Parameter url: `URL`
    /// - Returns: `String`으로 상대 경로 반환.
    func relativePath(of url: URL) -> String
    
    /// 특정 작업의 Request 반환
    /// - Parameters:
    ///   - operation: `FileOperationType`
    ///   - overwrite: 덮어쓰기
    /// - Returns: `URLRequest`. 실패 시 널값 반환.
    func request(for operation: FileOperationType,
                    overwrite: Bool) async -> URLRequest?
    /// 데이터 업로드 작업의 Request 반환
    /// - Parameters:
    ///   - destinationPath: 업로드 경로.
    /// - Returns: `URLRequest`. 실패 시 널값 반환.
    func requestForUploadData(to destinationPath: String) async -> URLRequest?
    /// 서버 에러 반환
    /// - Parameters:
    ///   - code: `HTTPErrorCode`
    ///   - path: 경로. 널값 지정 가능.
    ///   - data: response가 포함된 `Data`. 널값 지정 가능.
    /// - Returns: `HTTPError` 반환.
    func serverError(with code: HTTPErrorCode, path: String?, data: Data?) -> HTTPError
    /// 다중 Status 에러 반환
    /// - Parameters:
    ///   - operation: 작업 종류.
    ///   - data: response가 포함된 `Data`
    /// - Returns: HTTP 에러 반환.
    func multiStatusError(operation: FileOperationType, data: Data) -> HTTPError?
}

extension HTTPProviderable {
    // MARK: - Make Root FileItem
    /// FileItem 생성
    /// - 단독 FileItem을 생성하며, 주로 Root FileItem 생성에 사용한다.
    /// - Parameter path: 생성 경로.
    /// - Returns: 해당 경로의 `FileItem` 초기화 후 반환. 실패 시 에러를 던진다.
    public func makeItem(of path: String) async throws -> FileItem {
        try Task.checkCancellation()
        let result = await item(of: path)
        switch result {
        case .success(let fileItem):
            return fileItem
        case .failure(let error):
            throw error
        }
    }
    
    // MARK: - Session Property
    /// URL Session
    var session: URLSession {
        get {
            if _session == nil {
                self.sessionDelegate = SessionDelegate(provider: self, credential: credential)
                let config = URLSessionConfiguration.default
                config.urlCache = self.urlCache
                // 프로토콜 캐시 정책을 따른다
                // requestCachePolicy 는 dataTask 실행 시에만 캐시를 생성, 저장한다. downloadTask는 받는 즉시 삭제되는 것이 정상이다.
                config.requestCachePolicy = .useProtocolCachePolicy
                _session = URLSession(configuration: config, delegate: sessionDelegate as URLSessionDelegate?, delegateQueue: self.operationQueue)
            }
            return _session
        }
        
        set {
            assert(newValue.delegate is SessionDelegate<Self>, "session instances should have a SessionDelegate instance as delegate.")
            _session = newValue
        }
    }

    // MARK: - Methods
    
    // MARK: Information Methods
    
    /// 특정 경로가 디렉토리인지 여부를 반환하는 비동기 메쏘드
    public func isDirectory(of path: String) async -> Bool {
        let itemResult = await self.item(of: path)
        switch itemResult {
        case .success(let item):
            return item.isDirectory
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription).")
            return false
        }
    }

    // MARK: Download Method
    /// 특정 경로 파일의 크기를 구한다
    /// - Parameter path: 파일 경로를 지정한다.
    /// - Returns: Result 타입으로 UInt64 형의 길이를 반환한다. 실패 시 에러를 반환한다.
    public func fileSize(of path: String) async -> Result<UInt64, any Error> {
        // 경로 정규화 처리
        let path = path.precomposedStringWithCanonicalMapping
        let itemResult = await self.item(of: path)
        switch itemResult {
        case .success(let item):
            return .success(UInt64(item.fileSize))
            
        case .failure(let error):
            return .failure(error)
        }
    }

    /// 특정 경로의 전체 Data를 비동기로 반환
    /// - Parameters:
    ///   - path: 가져올 파일 경로.
    ///   - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 Data 또는 에러 반환
    public func data(of path: String, _ progressHandler: @escaping ProgressHandler) async -> Result<Data, any Error> {
        return await self.data(of: path,
                               offset: 0,
                               length: 0,
                               progressHandler)
    }
    /// 특정 경로의 일부 Data를 비동기로 반환
    /// - Important: 이 메쏘드는 다운로드 전에 캐쉬 데이터를 확인한다.
    /// - Parameters:
    ///   - path: 가져올 파일 경로.
    ///   - offset: 다운로드 개시 지점. 0인 경우 시작부터 다운로드.
    ///   - length: 다운로드 받을 데이터 길이. 0인 경우 전체 다운로드 실행.
    ///   - progressHandler: 전체 / 진행 상태 / 파일명 등을 받는다.
    /// - Returns: Result 타입으로 Data 또는 에러 값을 반환한다.
    public func data(of path: String,
                     offset: Int64,
                     length: Int64,
                     _ progressHandler: @escaping ProgressHandler) async -> Result<Data, Error> {
        
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            progressHandler(length, length, 1.0, .download, path.lastPathComponent)
            return .failure(Files.Error.abort)
        }

        // 경로 정규화 처리
        let path = path.precomposedStringWithCanonicalMapping
        let itemResult = await self.item(of: path)
        var totalFileSize: Int64 = 0
        switch itemResult {
        case .success(let fileItem):
            totalFileSize = fileItem.fileSize
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = 파일 속성 조회 실패.")
            progressHandler(length, length, 1.0, .error(error), path.lastPathComponent)
            return .failure(error)
        }

        // 길이가 0 이상으로 주어진 경우
        if length > 0 {
            guard totalFileSize > 0,
                  totalFileSize >= offset + (length >= 0 ? length : totalFileSize) else {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: offset/lenght(\(offset), \(length)) 값이 \(totalFileSize) 를 초과.")
                progressHandler(length, length, 1.0, .error(Files.Error.readFailedByWrongSize), path.lastPathComponent)
                return .failure(Files.Error.readFailedByWrongSize)
            }
        }
        
        let operation = FileOperationType.fetch(path: path)
        guard var request = await self.request(for: operation, overwrite: false) else {
            // request 생성 실패
            progressHandler(length, length, 1.0, .error(Files.Error.makeRequestFailed), path.lastPathComponent)
            return .failure(Files.Error.makeRequestFailed)
        }
        // length를 그대로 지정하면 된다. rangeWithOffset() 메쏘드에서 알아서 처리한다.
        request.setValue(rangeWithOffset: offset, length: Int(length))

        // URLCache는 Range 헤더를 캐쉬 키로 사용하지 않으므로, 범위 요청 시 offset/length를 URL
        // 쿼리 파라미터로 포함한 별도의 캐쉬 키 request를 사용해 범위별 충돌을 방지한다.
        var cacheKeyRequest = request
        if (offset > 0 || length > 0), let cacheURL = requestURL(at: path, offset: offset, length: length) {
            cacheKeyRequest.url = cacheURL
        }

        // 캐쉬 사용 시
        if urlCache != nil {
            let result = await self.returnCachedData(with: cacheKeyRequest, validatingCache: validatingCache)
            switch result {
            case .success(let cachedValue):
                // 성공 시 그대로 반환
                return .success(cachedValue.0)
            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 캐쉬 복원 중 에러 발생 = \(error.localizedDescription)")
                break
                // URL에서 직접 받아오는 작업을 실행한다.
            }
        }

        let downloadResult = await downloadToCachedURL(request: request, cacheKeyRequest: cacheKeyRequest, progressHandler: progressHandler)
        switch downloadResult {
        case .success(let data):
            return .success(data)
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// 특정 경로의 파일을 비동기로 로컬 URL에 다운로드
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - localFolder: 다운받을 로컬 폴더를 지정한다. 파일명은 그대로 유지한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 다운받은 파일 URL 또는 에러 반환
    public func download(from path: String,
                         toLocalFolder localFolder: URL,
                         conflictHandler: (@Sendable () async -> Files.Conflict)?,
                         _ progressHandler: @escaping ProgressHandler) async -> Result<URL, Error> {
        var saveURL: URL
        // 저장할 폴더에 파일명을 경로로 연결해 저장 URL을 만든다.
        if #available(macOS 13.0, *) {
            saveURL = localFolder.appending(path: path.lastPathComponent)
        }
        else {
            saveURL = localFolder.appendingPathComponent(path.lastPathComponent)
        }
        // 저장 경로 충돌 확인
        switch await resolveFileConflict(ofLocalURL: saveURL, conflictHandler) {
        case .success(let success):
            switch success {
            case true:
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(saveURL.filePath) >> 파일이 없거나, 덮어쓰기를 위해 제거되었습니다.")
                // 작업을 계속 진행하기 위해 중지 처리
                break

            case false:
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(saveURL.filePath) >> 파일이 이미 있으며, 건너뛰기를 실행하기로 결정되어 덮어쓰기 없이 종료합니다.")
                progressHandler(1, 1, 1.0, .download, path.lastPathComponent)
                return .success(saveURL)
            }
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(saveURL.filePath) >> 에러 발생 = \(error.localizedDescription)")
            progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
            return .failure(error)
        }
     
        let operation = FileOperationType.fetch(path: path)
        guard var request = await self.request(for: operation, overwrite: false) else {
            // request 생성 실패
            progressHandler(1, 1, 1.0, .error(Files.Error.makeRequestFailed), path.lastPathComponent)
            return .failure(Files.Error.makeRequestFailed)
        }
        // length를 그대로 지정하면 된다. rangeWithOffset() 메쏘드에서 알아서 처리한다.
        request.setValue(rangeWithOffset: 0, length: 0)
        
        // 캐쉬 사용 시
        if urlCache != nil {
            let result = await self.returnCachedData(with: request, validatingCache: validatingCache)
            switch result {
            case .success(let cachedValue):
                // 성공 시
                do {
                    try cachedValue.0.write(to: saveURL)
                    return .success(saveURL)
                }
                catch {
                    EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 파일 쓰기 에러 발생 = \(error.localizedDescription)")
                }
                
            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 캐쉬 복원 중 에러 발생 = \(error.localizedDescription)")
                break
                // URL에서 직접 받아오는 작업을 실행한다.
            }
        }

        let downloadResult = await downloadToCachedURL(request: request,
                                                       moveTemporaryFileURL: saveURL,
                                                       progressHandler: progressHandler)
        switch downloadResult {
        case .success(_):
            return .success(saveURL)
            
        case .failure(let error):
            return .failure(error)
        }

    }
    
    /// 실제 다운로드 실행 private 메쏘드
    /// - Parameters:
    ///   - request: `URLRequest`.
    ///   - cacheKeyRequest: 캐쉬 저장용 URL로, 범위 지정 시 캐쉬 구분을 위해 사용된다. 기본값은 널 값이다.
    ///   - moveTemporaryFileURL: 임시 파일을 복사해 넣을 URL. 미지정 시 임시 파일을 삭제하기만 한다. 기본값은 널 값이다.
    ///   - progressHandler: 전체 / 진행 상태 / 파일명 등을 받는다.
    /// - Returns: Result 타입으로 다운로드받은 data 또는 에러 값을 반환한다.
    private func downloadToCachedURL(request: URLRequest,
                                     cacheKeyRequest: URLRequest? = nil,
                                     moveTemporaryFileURL: URL? = nil,
                                     progressHandler: @escaping ProgressHandler) async -> Result<Data, Error> {
        // 전체 크기/진행상태 확인용 비동기 스트림 초기화
        let (progressStream, progressContinuation) = AsyncStream<TotalBytesAndProgressed>.makeStream()

        do {
            // dataTask 초기화
            let task = session.downloadTask(with: request)
                        
            let resultTask = Task<URL, Error> {
                // 작업 취소 여부 확인용 핸들러
                try await withTaskCancellationHandler {
                    // 연속성 핸들러
                    try await withCheckedThrowingContinuation { continuation in
                        Task {
                            // 연속성을 추가
                            await self.sessionDelegate?.addDownloadContinuations(forTask: task, progress: progressContinuation, result: continuation)
                            // 다운로드 작업 개시
                            task.resume()
                        }
                    }
                } onCancel: {
                    task.cancel()
                }
            }
            
            // 다른 쓰레드에서 progressHandler 업데이트
            Task {
                for await (totalBytes, progressedBytes) in progressStream {
                    let fractionCompleted: Double = Double(progressedBytes) / Double(totalBytes)
                    progressHandler(totalBytes, progressedBytes, fractionCompleted, .download, request.url?.lastPathComponent ?? "Unknown")
                }
            }

            // 취소 여부 확인
            try Task.checkCancellation()
            
            // sessionDelegate로 전달받은 임시 파일 URL
            let tempURL = try await resultTask.value
                        
            let fileManager = FileManager.default
            // scope 종료 시 임시 파일 삭제
            defer {
                try? fileManager.removeItem(at: tempURL)
            }
            
            guard let url = request.url else {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 알 수 없는 에러. 다운로드 URL을 확인할 수 없음.")
                return .failure(Files.Error.unknown)
            }
            
            let data = try Data(contentsOf: tempURL)
            // 임시 파일을 이동시킬 URL이 있는 경우, 이동 처리
            if let moveTemporaryFileURL {
                try fileManager.moveItem(at: tempURL, to: moveTemporaryFileURL)
            }

            // 캐쉬 저장 - 범위 요청 시 cacheKeyRequest(쿼리 파라미터 URL)로 저장해 키 충돌 방지
            let effectiveRequest = cacheKeyRequest ?? request
            let effectiveURL     = effectiveRequest.url ?? url
            await self.saveCacheData(data, for: effectiveURL, with: effectiveRequest)
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 다운로드 캐쉬 URL에 파일 등록 = \(effectiveURL.absoluteString)")
            return .success(data)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(error), request.url?.lastPathComponent ?? "Unknown")
            return .failure(error)
        }
    }
    
    // MARK: Upload Method
    
    /// 파일 업로드
    /// - Important: 폴더인 경우, 서버에 디렉토리를 생성하기만 한다. 폴더 내용까지 올리려면 `writeFolder` 메쏘드를 사용한다.
    /// - Parameters:
    ///    - localPath: 업로드할 로컬 파일 경로.
    ///    - remotePath: 파일이 올라갈 FTP 경로, 업로드할 파일/폴더명까지 포함해야 한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func write(from originPath: String,
                      to targetPath: String,
                      conflictHandler: (@Sendable () async -> Files.Conflict)? = nil,
                      _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, any Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            progressHandler(1, 1, 1.0, .cancel, targetPath.lastPathComponent)
            return .failure(Files.Error.abort)
        }

        // 경로 정규화 처리
        let originPath = originPath.precomposedStringWithCanonicalMapping
        let targetPath = targetPath.precomposedStringWithCanonicalMapping

        let url = URL(fileURLWithPath: originPath)
        guard FileManager.default.fileExists(atPath: url.filePath) else {
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(Files.Error.notExist), targetPath.lastPathComponent)
            return .failure(Files.Error.notExist)
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: originPath, isDirectory: &isDirectory) else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(originPath) >> 파일이 없음")
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(Files.Error.notExist), targetPath.lastPathComponent)
            // 파일이 없음
            return .failure(Files.Error.notExist)
        }

        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(originPath) >> 사용자 취소 발생.")
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .cancel, targetPath.lastPathComponent)
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }

        // 충돌 확인
        switch await resolveFileConflict(of: targetPath, conflictHandler) {
        case .success(let success):
            switch success {
            case true:
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 없거나, 덮어쓰기를 위해 제거되었습니다.")
                break

            case false:
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 이미 있으며, 건너뛰기를 실행하기로 결정되어 덮어쓰기 없이 종료합니다.")
                progressHandler(1, 1, 1.0, .write, targetPath.lastPathComponent)
                return .success(true)
            }
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 에러 발생 = \(error.localizedDescription)")
            progressHandler(1, 1, 1.0, .error(error), targetPath.lastPathComponent)
            return .failure(error)
        }
        
        guard isDirectory.boolValue == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 신규 폴더 생성.")
            progressHandler(1, 1, 1.0, .write, targetPath.lastPathComponent)
            // 폴더 생성 시도, 결과 반환
            return await self.create(of: targetPath)
        }
        
        let result = await self.upload(from: url,
                                       to: targetPath,
                                       progressHandler: progressHandler)
        switch result {
        case .success(_):
            return .success(true)
        case .failure(let error):
            return .failure(error)
        }
    }
    /// 파일 업로드 실행
    /// - Parameters:
    ///   - localURL: 업로드할 파일 `URL`.
    ///    - targetPath: 파일이 올라갈 FTP 경로.
    ///    - overwrite: 동일한 파일이 있는 경우, 충돌 여부를 확인.
    ///   - progressHandler: 전체 / 진행 상태 / 파일명 등을 받는다.
    /// - Returns: Result 타입으로 Response `Data` 또는 에러 값을 반환한다
    private func upload(from localURL: URL,
                       to path: String,
                       overwrite: Bool = false,
                       progressHandler: @escaping ProgressHandler) async -> Result<Data, Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            progressHandler(1, 1, 1.0, .cancel, path.lastPathComponent)
            return .failure(Files.Error.abort)
        }

        // 경로 정규화 처리
        let path = path.precomposedStringWithCanonicalMapping
        let operation = FileOperationType.copy(source: localURL.absoluteString, destination: path)
        guard let request = await self.request(for: operation, overwrite: overwrite) else {
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(Files.Error.makeRequestFailed), path.lastPathComponent)
            // request 생성 실패
            return .failure(Files.Error.makeRequestFailed)
        }
                
        let (progressStream, progressContinuation) = AsyncStream<TotalBytesAndProgressed>.makeStream()
        
        do {
            // dataTask 초기화
            let task = session.uploadTask(with: request, fromFile: localURL)
            
            let resultTask = Task<Data, Error> {
                // 작업 취소 여부 확인용 핸들러
                try await withTaskCancellationHandler {
                    // 연속성 핸들러
                    try await withCheckedThrowingContinuation { continuation in
                        Task {
                            // 연속성을 추가
                            await sessionDelegate?.addUploadContinuations(forTask: task, progress: progressContinuation, result: continuation, totalSize: Int64(localURL.fileSize))
                            // 다운로드 작업 개시
                            task.resume()
                        }
                    }
                } onCancel: {
                    task.cancel()
                }
            }
            
            let filename = request.url?.lastPathComponent ?? "Unknown"
            // 다른 쓰레드에서 progressHandler 업데이트
            Task {
                for await (totalBytes, progressedBytes) in progressStream {
                    let fractionCompleted: Double = Double(progressedBytes) / Double(totalBytes)
                    progressHandler(totalBytes, progressedBytes, fractionCompleted, .write, filename)
                }
            }

            // 취소 여부 확인
            try Task.checkCancellation()

            let data = try await resultTask.value            
            return .success(data)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
            return .failure(error)
        }
    }
    /// 데이터 업로드
    /// - Parameters:
    ///    - data: 업로드할 Data
    ///    - targetPath: 파일이 올라갈 FTP 경로
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func write(from data: Data,
                      to targetPath: String,
                      conflictHandler: (@Sendable () async -> Files.Conflict)? = nil,
                      _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            progressHandler(1, 1, 1.0, .cancel, targetPath.lastPathComponent)
            return .failure(Files.Error.abort)
        }
        
        // 경로 정규화 처리
        let targetPath = targetPath.precomposedStringWithCanonicalMapping
        guard let request = await self.requestForUploadData(to: targetPath) else {
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(Files.Error.makeRequestFailed), targetPath.lastPathComponent)
            // request 생성 실패
            return .failure(Files.Error.makeRequestFailed)
        }
        do {
            defer {
                // 완료 핸들러 업데이트
                progressHandler(1, 1, 1.0, .write, targetPath.lastPathComponent)
            }
            
            // 취소 여부 확인
            try Task.checkCancellation()
            
            // 충돌 확인
            switch await resolveFileConflict(of: targetPath, conflictHandler) {
            case .success(let success):
                switch success {
                case true:
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 없거나, 덮어쓰기를 위해 제거되었습니다.")
                    break

                case false:
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 이미 있으며, 건너뛰기를 실행하기로 결정되어 덮어쓰기 없이 종료합니다.")
                    progressHandler(1, 1, 1.0, .write, targetPath.lastPathComponent)
                    return .success(true)
                }
                
            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 에러 발생 = \(error.localizedDescription)")
                progressHandler(1, 1, 1.0, .error(error), targetPath.lastPathComponent)
                return .failure(error)
            }

            let resultData: Data
            let response: URLResponse
            if #available(macOS 12.0, iOS 15.0, *) {
                let result = try await self.session.upload(for: request, from: data, delegate: self.sessionDelegate)
                resultData = result.0
                response = result.1
            } else {
                let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                    let task = self.session.uploadTask(with: request, from: data) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let data = data, let response = response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    task.resume()
                }
                resultData = result.0
                response = result.1
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생, 원인 불명.")
                throw Files.Error.unknown
            }
            
            // A successful WebDAV upload (PUT) usually returns 200, 201, or 204
            guard (200...299).contains(httpResponse.statusCode) else {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 서버 에러 발생 = \(httpResponse.statusCode)")
                if let code = HTTPErrorCode(rawValue: httpResponse.statusCode) {
                    throw self.serverError(with: code, path: targetPath, data: resultData)
                }
                else {
                    throw Files.Error.sendFailed
                }
            }
            // 성공 처리
            return .success(true)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            // 완료 핸들러 업데이트
            progressHandler(1, 1, 1.0, .error(error), targetPath.lastPathComponent)
            return .failure(error)
        }
    }

    // MARK: - Resolve Conflict

    /// 특정 경로 파일의 충돌 확인
    /// - 파일 충돌이 발생하는 경우, 사용자에게 덮어쓰기/병합/건너뛰기 여부를 확인한다.
    /// - Parameters:
    ///   - path: 파일 충돌 여부 확인 경로.
    ///   - conflictHandler: 덮어쓰기/병합/거너뛰기 확인용 완료 핸들러.
    /// - Returns: Result 타입으로 충돌 파일이 없거나 기존 파일을 삭제하는 데 성공하면 true를 반환한다.
    /// 기존 파일이 있지만 병합/건너뛰기 발생 시에는 false를 반환한다.
    /// 충돌이 있는데도 사용자 확인을 받지 못한 경우, 또는 삭제 중 문제가 발생하면 에러를 반환한다.
    public func resolveFileConflict(of path: String, _ conflictHandler: (@Sendable () async -> Files.Conflict)?) async -> Result<Bool, Error> {
        let itemResult = await item(of: path)
        guard case let .success(item) = itemResult else {
            // 파일이 없기 때문에 덮어쓰기 불필요.
            return .success(true)
        }
        guard let conflictHandler else {
            // 충돌 여부를 사용자에게 확인하지 않는 경우
            return .failure(Files.Error.disallowOverwrite)
        }
        
        // 확인 결과
        return await resolveFileConflict(isDirectory: item.isDirectory, conflictHandler) {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 덮어쓰기를 위해 기존 파일 및 폴더를 제거합니다.")
            return await self.remove(item)
        }
    }
    
    // MARK: - Create Folder Method
    /// 폴더 생성 메쏘드
    /// - Parameters:
    ///   - folderName: 작성할 폴더 명.
    ///   - atPath: 폴더가 작성될 경로.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    func create(folder folderName: String, in inPath: String) async -> Result<Bool, Error> {
        let path = inPath.appendingPathComponent(folderName)
        return await self.create(of: path)
    }
    /// 폴더 생성 메쏘드
    /// - Parameter path: 폴더가 작성될 경로와 폴더 명까지 포함한 경로 지정.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    func create(of path: String) async -> Result<Bool, Error> {
        // 마지막 경로명에 /를 붙인다 (만일을 위해 경로명 마지막의 슬래쉬를 제거한 다음 추가하도록 한다)
        return await doOperation(.create(path: path.removedLastSlash() + "/"))
    }

    // MARK: - Common Operate Method
    /// 복사 / 이동 / 폴더 생성 / 삭제 등 공통 작업 처리
    /// - Parameters:
    ///   - operation: `FileOperationType` 으로 작업 지정. 복사 / 이동 / 폴더 생성 / 삭제 등으로 한정된다.
    ///   - overwrite: 덮어쓰기 여부. 기본값은 false.
    /// - Returns: Result 타입으로 성공 또는 에러 반환.
    internal func doOperation(_ operation: FileOperationType,
                              overwrite: Bool = false) async -> Result<Bool, Error> {
        
        guard let request = await self.request(for: operation, overwrite: overwrite) else {
            // request 생성 실패
            return .failure(Files.Error.makeRequestFailed)
        }
                
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            let data: Data
            let response: URLResponse
            if #available(macOS 12.0, iOS 15.0, *) {
                let result = try await self.session.data(for: request, delegate: sessionDelegate)
                data = result.0
                response = result.1
            } else {
                let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                    let task = self.session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let data = data, let response = response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    task.resume()
                }
                data = result.0
                response = result.1
            }
            if let response = response as? HTTPURLResponse {
                if response.statusCode >= 300 {
                    if let code = HTTPErrorCode(rawValue: response.statusCode) {
                        throw self.serverError(with: code, path: operation.source, data: data)
                    }
                    else {
                        throw Files.Error.unknown
                    }
                }
                
                if HTTPErrorCode(rawValue: response.statusCode) == .multiStatus,
                   let ms_error = self.multiStatusError(operation: operation, data: data) {
                    throw ms_error
                }
            }
            
            // 성공 시
            switch operation {
                // 삭제 시 캐쉬 제거
            case .remove(path: _):
                urlCache?.removeCachedResponse(for: request)

            case .move(source: let originPath, destination: let taretPath):
                let originOperation = FileOperationType.fetch(path: originPath)
                let targetOperation = FileOperationType.fetch(path: taretPath)
                if let originRequest = await self.request(for: originOperation, overwrite: false),
                   let targetRequest = await self.request(for: targetOperation, overwrite: false) {
                    urlCache?.moveCache(from: originRequest, to: targetRequest)
                }
                
                // 그 외의 경우
            default:
                break
            }

            return .success(true)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    // MARK: - Data Task Method
    /// Data Task 실행 후 완료 핸들러로 결과 반환
    /// - Important: `URLCache` 프로퍼티가 nil이 아닌 경우, 캐쉬가 있다면 캐쉬 값으로 반환 처리한다.
    /// - Parameter request: `URLRequest`
    /// - Returns: `Data` / `URLResponse`의 튜플을 반환한다. 에러 발생 시 `Error` 를 반환한다.
    func doDataTask(with request: URLRequest) async -> Result<(Data, URLResponse), Error> {
        if urlCache != nil {
            let result = await self.returnDataTaskCachedData(with: request, validatingCache: validatingCache)
            switch result {
            case .success(_):
                // 성공 시 그대로 반환
                return result
            case .failure(_):
                /// # 로그 비활성화
                /// 사실상 캐쉬 재사용이 안되는 경우가 많기 때문에 로그를 찍는 것이 현재로서는 무의미하다.
                //EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 캐쉬 복원 중 에러 발생 = \(error.localizedDescription)")
                break
                // URL에서 직접 받아오는 작업을 실행한다.
            }
        }

        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            let result: (Data, URLResponse)
            if #available(macOS 12.0, iOS 15.0, *) {
                result = try await self.session.data(for: request, delegate: sessionDelegate)
            } else {
                result = try await withCheckedThrowingContinuation { continuation in
                    let task = self.session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let data = data, let response = response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    task.resume()
                }
            }
            try Task.checkCancellation()
            return .success(result)
        }
        catch {
            // 에러 발생
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    // MARK: - URLCache Method
    /// URLCache에 DataTask데이터 생성 후 반환
    /// - Important: `URLCache`는 임시 저장 파일 경로를 직접 반환해 주지 않기 때문에 `Data`로만 반환한다.
    /// - `URLCache` 가 NIL이 아닌 경우, `doDataTask(with:)` 메쏘드에서 호출한다.
    /// - Parameters:
    ///   - request: `URLRequest`로 가져올 데이터를 찾는다.
    ///   - validatingCache: 캐쉬 유효성 확인 여부. true 로 지정하면 헤더 값을 가져와 비교해, 변경이 발생한 경우에는 데이터를 새로 내려받는다.
    /// - Returns: Result 타입으로 Data와 URLResponse 튜플, 또는 에러 반환.
    private func returnDataTaskCachedData(with request: URLRequest, validatingCache: Bool) async -> Result<(Data, URLResponse), Error> {
        guard let urlCache,
              let cachedResponse = urlCache.cachedResponse(for: request) else {
            return .failure(Files.Error.accessToURLCacheFailed)
        }

        if let httpResponse = cachedResponse.response as? HTTPURLResponse {
            // 캐쉬 유효성 검사 결과
            var validatedCache = !validatingCache
            let lastModifiedDate = httpResponse.allHeaderFields["Last-Modified"] as? String
            let eTag = httpResponse.allHeaderFields["ETag"] as? String
            do {
                // 취소 여부 확인
                try Task.checkCancellation()

                // 유효성 검사가 필요한지, 그리고 eTag와 수정일이 확인되는지 확인한다.
                if lastModifiedDate == nil && eTag == nil,
                   validatingCache {
                    // 유효성 검사 진행
                    // 헤더 값만 다운받도록 한다.
                    var validateRequest = request
                    validateRequest.httpMethod = "HEAD"
                    let response: URLResponse
                    if #available(macOS 12.0, iOS 15.0, *) {
                        let result = try await self.session.data(for: validateRequest, delegate: sessionDelegate)
                        response = result.1
                    } else {
                        let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                            let task = self.session.dataTask(with: validateRequest) { data, response, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                    return
                                }
                                if let data = data, let response = response {
                                    continuation.resume(returning: (data, response))
                                } else {
                                    continuation.resume(throwing: URLError(.badServerResponse))
                                }
                            }
                            task.resume()
                        }
                        response = result.1
                    }
                    if let httpResponse = response as? HTTPURLResponse {
                        let currentETag = httpResponse.allHeaderFields["ETag"] as? String
                        let currentLastModifiedDate = httpResponse.allHeaderFields["ETag"] as? String ?? "nonvalidetag"
                        // 기존 eTag와 현재 eTag가 일치하고, 기존 수정일과 현재 수정일이 일치하는지 확인한다.
                        validatedCache = (eTag != nil && currentETag == eTag) || (lastModifiedDate != nil && currentLastModifiedDate == lastModifiedDate)
                    }
                }
                
                guard validatedCache == true else {
                    // 갱신이 필요한 경우
                    return .failure(Files.Error.updateURLCacheIsNeeded)
                }
                // 유효성이 확인된 경우 또는 유효성 검사 생략 시 데이터 반환
                return .success((cachedResponse.data, cachedResponse.response))
            }
            catch {
                // 에러 발생
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
                return .failure(error)
            }
        }
        else {
            // 캐쉬 접근 실패 에러
            return .failure(Files.Error.accessToURLCacheFailed)
        }
    }
    
    // MARK: - Paginate Methods
    
    
    /// Paginated 처리 메쏘드
    /// - 페이지 처리된 데이터에서 디렉토리 구조를 가져오는 메쏘드로 WebDAV를 제외한 대부분의 HTTP 프로토콜이 사용한다.
    /// - Parameters:
    ///   - path: 경로.
    ///   - requestHandler: 생성용 토큰으로 `URLRequest`를 반환하는 핸들러. 널값으로 반환할 수도 있기 때문에 에러 처리가 필요하다.
    ///   - pageHandler: 페이지 내용을 받아 파일아이템 배열 또는 에러를 반환하는 핸들러.
    /// - Returns: Result 타입으로 파일아이템 배열 또는 에러 반환.
    internal func paginated(_ path: String,
                            requestHandler: @escaping (_ token: String?) async -> URLRequest?,
                            pageHandler: @escaping (_ data: Data?) async -> (files: [FileItem], error: Error?, newToken: String?)) async -> Result<[FileItem], Error> {
        return await self.paginated(path, startToken: nil, previousResult: [], requestHandler: requestHandler, pageHandler: pageHandler)
    }
    /// Paginated 실제 처리용 private 메쏘드
    /// - 페이지 처리된 데이터에서 디렉토리 구조를 가져오는 메쏘드로 WebDAV를 제외한 대부분의 HTTP 프로토콜이 사용한다.
    /// - Parameters:
    ///   - path: 경로.
    ///   - startToken: 시작 토큰값. 널값 지정 가능.
    ///   - previousResult: 전 페이지에서 생성된 파일아이템 배열.
    ///   - requestHandler: 생성용 토큰으로 `URLRequest`를 반환하는 핸들러. 널값으로 반환할 수도 있기 때문에 에러 처리가 필요하다.
    ///   - pageHandler: 페이지 내용을 받아 파일아이템 배열 또는 에러를 반환하는 핸들러.
    /// - Returns: Result 타입으로 파일아이템 배열 또는 에러 반환.
    private func paginated(_ path: String,
                           startToken: String?,
                           previousResult: [FileItem],
                           requestHandler: @escaping (_ token: String?) async -> URLRequest?,
                           pageHandler: @escaping (_ data: Data?) async -> (files: [FileItem], error: Error?, newToken: String?)) async -> Result<[FileItem], Error> {
        
        guard let request = await requestHandler(startToken) else {
            return .failure(Files.Error.findRequestFailed)
        }
        
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            let data: Data
            let response: URLResponse
            if #available(macOS 12.0, iOS 15.0, *) {
                let result = try await self.session.data(for: request)
                data = result.0
                response = result.1
            } else {
                let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                    let task = self.session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let data = data, let response = response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    task.resume()
                }
                data = result.0
                response = result.1
            }
         
            if let code = (response as? HTTPURLResponse)?.statusCode,
                code >= 300 {
                if let rCode = HTTPErrorCode(rawValue: code) {
                    throw self.serverError(with: rCode, path: path, data: data)
                }
                else {
                    throw Files.Error.unknown
                }
            }
            
            let (newFiles, err, newToken) = await pageHandler(data)
            if let error = err {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 파일 Fetch 중 에러 발생 = \(error.localizedDescription)")
                throw error
            }
            
            // 취소 여부 확인
            try Task.checkCancellation()

            let fileItems = previousResult + newFiles
            if let newToken = newToken {
                return await self.paginated(path, startToken: newToken, previousResult: fileItems, requestHandler: requestHandler, pageHandler: pageHandler)
            } else {
                return .success(fileItems)
            }
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    // MARK: - Exsitance Method
    /// 해당 경로에 파일 또는 폴더 존재 여부
    func fileExists(of path: String) async -> Bool {
        let result = await item(of: path)
        if case .success = result {
            return true
        }
        return false
    }
}

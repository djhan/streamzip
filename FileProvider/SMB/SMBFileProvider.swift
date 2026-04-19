//
//  SMBFileProvider.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/29/25.
//

import Foundation

import CommonLibrary
/// 동시성 에러를 해결하기 위해 @preconcurrency를 추가해서 임포트한다.
@preconcurrency internal import SMBClient
/// SMBClient를 @unchecked Sendable로 확장
extension SMBClient: @unchecked @retroactive Sendable {
 
}

// MARK: - SMB File Provider Actor -

/// SMB File Provider Actor
/// - Important:
///   - 정상적인 사용을 위해 drive 명을 먼저 지정해야 한다. drive가 nil 인 경우, 드라이브 미지정 에러를 반환한다.
///   - 단, SMBClient 내부적으로 경로 정규화를 실행하므로 사용 시 경로를 정규화할 필요는 없다.
public actor SMBFileProvider: FileProviderable {
    
    // MARK: - Properties
    
    public typealias FileItem = SMBItem
    /// Base URL
    public var baseURL: URL?
    public weak var urlCache: URLCache?
    
    /// SMB Host
    private let host: String
    /// 사용자 이름
    private let username: String
    /// 비밀번호
    private let password: String
    /// 포트
    private let port: Int
    /// 선택 Drive
    public var drive: String?
    
    /// SMB Client
    private var client: SMBClient?

    
    // MARK: - Deinitialization
    deinit {
        Task { [client] in
            try await client?.disconnectShare()
            try await client?.logoff()
            // 여기선 Logger가 작동하지 않는다.
            print("\(#file):\(#function) :: 해제 완료")
        }
    }

    // MARK: - Initialization
    
    /// 초기화
    /// - Important: 드라이브를 미지정하고 초기화한다면 초기화 이후에 `setDrive(_:)`를 사용해 드라이브를 지정해야만 한다.
    /// - Parameters:
    ///   - host: Host 주소.
    ///   - username: 사용자 명.
    ///   - password: 비밀번호.
    ///   - port: 포트 번호. 기본값은 445다.
    ///   - drive: 접속할 드라이브. 기본값은 널값이다. 단, 미 지정 상태로는 `listDrives()`와 `setDrive(_:)`를 제외한 대부분의 메쏘드 사용이 불가능하다.
    ///   - urlCache: 파일을 임시 저장할 수 있는 `URLCache` 지정. 기본값은 널값이다.
    public init(host: String,
                username: String,
                password: String,
                port: Int = 445,
                drive: String? = nil,
                urlCache: URLCache? = nil) {
        self.host = host
        self.username = username
        self.password = password
        self.port = port
        self.drive = drive

        var urlComponents = URLComponents()
        urlComponents.scheme = "smb"
        urlComponents.host = host
        urlComponents.port = port
        urlComponents.user = username
        urlComponents.password = password
        urlComponents.path = drive != nil ? drive! : "/"

        self.baseURL = urlComponents.url
        self.urlCache = urlCache
    }
    

    // MARK: - Connection
    /// 드라이브 목록 가져오기
    /// - Returns: Result 타입으로 성공 시 드라이브 명 `String` 배열 반환. 실패 시 에러 반환.
    public func listDrives() async -> Result<[String], Error> {
        do {
            // client 연결
            let client = SMBClient(host: host, port: port)
            try await client.login(username: username, password: password)
            
            // share 목록을 가져온다
            let drives = try await client.listShares().compactMap { share -> String? in
                // disk 명칭만 반환
                guard share.name != "print$",
                    share.type == .diskTree else { return nil }
                return share.name
            }
            
            // client 연결 해제
            // share 연결이 안 되었으므로 disconnectShare() 호출은 불필요하다
            try await client.logoff()
            // share 목록 반환
            return .success(drives)
        }
        catch {
            // 에러 발생 시
            return .failure(error)
        }
    }
    /// 드라이브 지정
    public func setDrive(_ drive: String) {
        self.drive = drive
    }

    /// 연결 메쏘드
    /// - Returns: `SMBClient` 를 반환. 실패 시 에러를 던진다.
    private func connect() async throws -> SMBClient  {
        guard let drive else {
            // 드라이브 미 지정 시 에러 반환
            throw Files.Error.noDrive
        }

        if let client {
            // 기존 client의 연결 상태를 5초 타임아웃으로 검증한다.
            do {
                _ = try await withTimeout(seconds: 5) {
                    try await client.keepAlive()
                }
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(self.host) >> 기존 client를 반환합니다.")
                return client
            } catch {
                // keepAlive 실패(stale 연결 또는 타임아웃) → 재연결
                EdgeLogger.shared.networkLogger.warning("\(#file):\(#function) :: \(self.host) >> 기존 client 연결 확인 실패. 재연결합니다. 에러 = \(error.localizedDescription)")
                self.client = nil
            }
        }
        
        EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(self.host) >> client를 초기화합니다.")
        // 연결 시도
        self.client = SMBClient(host: host, port: port)
        guard let client else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(self.host) >> 서버에 연결할 수 없습니다.")
            // 서버 연결 실패
            throw Files.Error.connectToServerFailed
        }
        try await client.login(username: username, password: password)
        try await client.connectShare(drive)
        return client
    }
    /// 연결 종료 처리 메쏘드
    /// - Important: 필요하다고 판단되는 경우, 수동으로 disconnect를 실시한다. 특별한 경우가 아니라면 연결을 유지하고 deinit 시 자동으로 연결을 해제하도록 한다.
    /// - 실패 시 에러를 던진다.
    private func disconnect(_ client: SMBClient) async throws {
        try await client.disconnectShare()
        try await client.logoff()
    }

    /// 타임아웃을 적용한 비동기 작업 실행
    /// - Parameters:
    ///   - seconds: 타임아웃 시간(초).
    ///   - operation: 실행할 비동기 작업.
    /// - Returns: 작업 결과. 타임아웃 발생 시 `Files.Error.connectToServerFailed`를 던진다.
    private func withTimeout<T: Sendable>(seconds: TimeInterval,
                                          operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Files.Error.connectToServerFailed
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - SMB Methods
    
    // MARK: - Information Methods

    /// 특정 경로가 디렉토리인지 여부를 반환하는 비동기 메쏘드
    public func isDirectory(of path: String) async -> Bool {
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            // 연결 개시
            let client = try await self.connect()
            
            let fileInformation = try await withTimeout(seconds: 15) {
                try await client.fileInfo(path: path)
            }
            return fileInformation.standardInformation.directory
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> 에러 발생 = \(error.localizedDescription)")
            self.client = nil
            return false
        }
    }
    
    /// FileItem 생성
    /// - 단독 FileItem을 생성하며, 주로 Root FileItem 생성에 사용한다.
    /// - Parameter path: 생성 경로.
    /// - Returns: 해당 경로의 `FileItem` 초기화 후 반환. 실패 시 에러를 던진다.
    public func makeItem(of path: String) async throws -> FileItem {
        // 취소 여부 확인
        try Task.checkCancellation()
        // 연결 개시
        let client = try await self.connect()
        let fileInformation = try await withTimeout(seconds: 15) {
            try await client.fileInfo(path: path)
        }
        // 각 패러미터 설정
        let filename = fileInformation.nameInformation.fileName
        let fileSize = Int64(fileInformation.standardInformation.endOfFile)
        let isDirectory = fileInformation.standardInformation.directory
        let isHidden = fileInformation.basicInformation.fileAttributes.contains(.hidden)
        let isReadOnly = fileInformation.basicInformation.fileAttributes.contains(.readonly)
        let isSystem = fileInformation.basicInformation.fileAttributes.contains(.system)
        let isArchive = fileInformation.basicInformation.fileAttributes.contains(.archive)
        let creationTime = fileInformation.basicInformation.creationTime
        let lastAccessTime = fileInformation.basicInformation.lastAccessTime
        // 초기화
        let rootItem = SMBItem(path: path,
                               filename: filename,
                               creationDate: creationTime,
                               lastAccess: lastAccessTime,
                               fileSize: fileSize,
                               isDirectory: isDirectory,
                               isHidden: isHidden,
                               isReadOnly: isReadOnly,
                               isSystem: isSystem,
                               isArchive: isArchive)
        return rootItem
    }
    
    // MARK: - Listing Methods
    /// 특정 path 아래의 contents 아이템 목록을 `SMBItem` 배열로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    /// - Returns: `Result` 타입으로 `SMBItem` 배열 또는 에러 반환.
    public func contents(of path: String,
                         showHiddenFiles: Bool) async -> Result<[SMBItem], any Error> {
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            // 연결 개시
            let client = try await self.connect()
            
            let files = try await withTimeout(seconds: 30) {
                try await client.listDirectory(path: path)
            }
            let smbItems = files.compactMap { (file) -> SMBItem? in
                let smbItem = SMBItem(file, at: path)
                if showHiddenFiles == false {
                    // 감춤 파일 표시가 false 인 경우
                    guard smbItem.isHidden == false else {
                        return nil
                    }
                }
                return smbItem
            }
            return .success(smbItems)
        }
        catch {
            self.client = nil
            return .failure(error)
        }
    }

    // MARK: - Download Methods
    /// 특정 경로 파일의 크기를 구한다
    /// - Parameter path: 파일 경로를 지정한다.
    /// - Returns: Result 타입으로 UInt64 형의 길이를 반환한다. 실패 시 에러를 반환한다.
    public func fileSize(of path: String) async -> Result<UInt64, Error> {
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            // 연결 개시
            let client = try await self.connect()
            
            let fileInformation = try await withTimeout(seconds: 15) {
                try await client.fileInfo(path: path)
            }
            let fileSize = UInt64(fileInformation.standardInformation.endOfFile)

            guard fileSize > 0 else {
                // 파일 크기 0.
                return .failure(Files.Error.zeroFileSize)
            }
            return .success(fileSize)
        }
        catch {
            self.client = nil
            return .failure(error)
        }
    }

    /// 특정 경로의 전체 Data를 비동기로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 Data 또는 에러 반환
    public func data(of path: String, _ progressHandler: @escaping ProgressHandler) async -> Result<Data, any Error> {
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            // 연결 개시
            let client = try await self.connect()
            
            let fileInformation = try await withTimeout(seconds: 15) {
                try await client.fileInfo(path: path)
            }
            let fileSize = Int64(fileInformation.standardInformation.endOfFile)
            guard fileSize > 0 else {
                // 완료 처리
                progressHandler(1, 1, 1.0, .error(Files.Error.readFailedByIncomplete), path.lastPathComponent)
                // 파일 크기 0. 불완전 읽기로 실패 처리.
                return .failure(Files.Error.readFailedByIncomplete)
            }

            // File의 Request를 생성
            guard let requestURL = requestURL(at: path) else {
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .error(Files.Error.invalidURL), path.lastPathComponent)
                return .failure(Files.Error.invalidURL)
            }
            let request = URLRequest.createNoneHTTPRequest(requestURL)
            
            // 캐쉬 데이터 로딩 실행
            let cachedResult = await self.returnCachedData(with: request, validatingCache: false)
            if case let .success(result) = cachedResult  {
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .download, path.lastPathComponent)
                // 캐쉬 데이터 반환
                return .success(result.0)
            }

            // 취소 여부 확인
            try Task.checkCancellation()

            let data = try await withTimeout(seconds: 300) {
                try await client.download(path: path) { progress in
                    let progressed = Int64(Double(fileSize) * progress)
                    let fractionCompleted: Double = Double(progressed) / Double(fileSize)
                    progressHandler(fileSize, progressed, fractionCompleted, .download, path.lastPathComponent)
                }
            }

            // 완료 처리
            progressHandler(fileSize, fileSize, 1.0, .download, path.lastPathComponent)
            // 캐쉬 데이터 저장
            await self.saveCacheData(data, for: requestURL, with: request)
            // 데이터 반환
            return .success(data)
        }
        catch {
            self.client = nil
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
            return .failure(error)
        }
    }

    /// 특정 경로의 특정 영역의 Data를 비동기로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - offset: 다운로드 개시 지점. 0인 경우 시작부터 다운로드.
    ///    - length: 다운로드 받을 데이터 길이. 0인 경우 전체 다운로드 실행.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 Data 또는 에러 반환
    public func data(of path: String,
                      offset: Int64,
                      length: Int64,
                      _ progressHandler: @escaping ProgressHandler) async -> Result<Data, any Error> {
        do {
            // 취소 여부 확인
            try Task.checkCancellation()

            // 연결 개시
            let client = try await self.connect()
            
            let fileInformation = try await withTimeout(seconds: 15) {
                try await client.fileInfo(path: path)
            }
            let fileSize = Int64(fileInformation.standardInformation.endOfFile)
            guard fileSize > 0 else {
                // 완료 처리
                progressHandler(1, 1, 1.0, .error(Files.Error.readFailedByIncomplete), path.lastPathComponent)
                // 파일 크기 0. 불완전 읽기로 실패 처리.
                return .failure(Files.Error.readFailedByIncomplete)
            }
            guard fileSize >= offset,
                    fileSize >= offset + length else {
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .error(Files.Error.readFailedByWrongSize), path.lastPathComponent)
                // 잘못된 크기 지정
                return .failure(Files.Error.readFailedByWrongSize)
            }
            
            guard let requestURL = requestURL(at: path, offset: offset, length: length) else {
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .error(Files.Error.invalidURL), path.lastPathComponent)
                return .failure(Files.Error.invalidURL)
            }
            let request = URLRequest.createNoneHTTPRequest(requestURL)
            
            // 캐쉬 데이터 로딩 실행
            let cachedResult = await self.returnCachedData(with: request, validatingCache: false)
            if case let .success(result) = cachedResult  {
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .download, path.lastPathComponent)
                // 캐쉬 데이터 반환
                return .success(result.0)
            }
            
            // 취소 여부 확인
            try Task.checkCancellation()

            let data = try await withTimeout(seconds: 60) {
                try await client.download(path: path, offset: UInt64(offset), length: UInt32(length)) { progress in
                    let progressed = Int64(Double(length) * progress)
                    let fractionCompleted: Double = Double(progressed) / Double(length)
                    progressHandler(length, progressed, fractionCompleted, .download, path.lastPathComponent)
                }
            }

            // 완료 처리
            progressHandler(fileSize, fileSize, 1.0, .download, path.lastPathComponent)
            // 캐쉬 데이터 저장
            await self.saveCacheData(data, for: requestURL, with: request)
            // 데이터 반환
            return .success(data)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> 다운로드 도중 에러가 발생했습니다. 에러 = \(error.localizedDescription)")
            self.client = nil
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
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
        // 저장할 폴더에 파일명을 경로로 연결해 저장 URL을 만든다.
        let saveURL: URL
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

        var request: URLRequest
        // File의 Request를 생성
        guard let requestUrl = requestURL(at: path) else {
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(Files.Error.invalidURL), path.lastPathComponent)
            return .failure(Files.Error.invalidURL)
        }
        request = URLRequest.createNoneHTTPRequest(requestUrl)
        // 캐쉬 데이터 로딩 실행
        let cachedResult = await self.returnCachedData(with: request, validatingCache: false)
        if case let .success(result) = cachedResult  {
            do {
                try result.0.write(to: saveURL)
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(saveURL.filePath) >> 파일을 저장하는 데 성공했습니다.")
                progressHandler(1, 1, 1.0, .download, path.lastPathComponent)
                return .success(saveURL)
            }
            catch {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(saveURL.filePath) >> 저장 도중 에러가 발생했습니다. 에러 = \(error.localizedDescription)")
                progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
                return .failure(error)
            }
        }
        
        // 캐쉬가 발견되지 않은 경우

        do {
            // 연결 개시
            let client = try await self.connect()
            // 성공/실패 관계없이 완료 후 연결을 반납해 stale connection을 방지한다.
            defer { self.client = nil }

            let fileInformation = try await withTimeout(seconds: 15) {
                try await client.fileInfo(path: path)
            }
            let fileSize = Int64(fileInformation.standardInformation.endOfFile)

            guard fileSize > 0 else {
                // 파일 크기 0.
                return .failure(Files.Error.zeroFileSize)
            }

            try await withTimeout(seconds: 300) {
                try await client.download(path: path, localPath: saveURL, overwrite: true) { fraction in
                    let progressed = Int64(Double(fileSize) * fraction)
                    progressHandler(fileSize, progressed, fraction, .download, path.lastPathComponent)
                }
            }

            return .success(saveURL)
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(saveURL.filePath) >> 다운로드 도중 에러가 발생했습니다. 에러 = \(error.localizedDescription)")
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(error), path.lastPathComponent)
            return .failure(error)
        }
    }

    // MARK: - Operation Methods

    /// 특정 `SMBItem` 제거
    /// - Parameters:
    ///    - item: 제거할 `SMBItem`
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(_ item: SMBItem) async -> Result<Bool, any Error> {
        do {
            try await removeRecursvely(item.path, isDirectory: item.isDirectory)
            return .success(true)
        }
        catch {
            return .failure(error)
        }
    }
    /// 특정 경로의 파일 제거
    /// - Parameters:
    ///    - path: 제거할 파일 경로.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(of path: String) async -> Result<Bool, Error> {
        do {
            try await removeRecursvely(path)
            return .success(true)
        }
        catch {
            return .failure(error)
        }
    }
    /// 특정 경로의 파일 및 폴더를 재귀적으로 제거하는 private 메쏘드
    /// - Important: SMB는 파일이 있는 폴더를 삭제할 수 없으므로, 재귀적으로 내부 파일을 다 삭제해야 한다.
    /// - Parameters:
    ///    - path: 제거할 파일 경로.
    ///    - isDirectory: 제거할 파일 경로의 디렉토리 여부. 기본값은 널값.
    private func removeRecursvely(_ path: String,
                                  isDirectory: Bool? = nil) async throws {
        // 작업 취소 여부 확인
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 사용자 취소 발생.")
            throw Files.Error.abort
        }

        do {
            // 연결 개시
            let client = try await self.connect()

            // isDirectory가 널값인 경우, 파일 정보 획득
            let isDirectory = isDirectory != nil ? isDirectory! : try await client.fileInfo(path: path).standardInformation.directory
            switch isDirectory {
                // 폴더인 경우
            case true:
                let files = try await client.listDirectory(path: path)
                for file in files {
                    if file.name.hasPrefix(".") {
                        EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(file.name) >> . 으로 상위 디렉토리를 의미함. 건너뛴다.")
                        continue
                    }
                    // 하위 경로를 재귀적으로 삭제 처리
                    try await self.removeRecursvely(path.appendingPathComponent(file.name), isDirectory: file.isDirectory)
                }
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 폴더 제거.")
                // 내부 파일이 모두 제거된 폴더를 제거
                try await client.deleteDirectory(path: path)

                // 파일인 경우
            case false:
                // 제거 실행
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 파일 제거.")
                try await client.deleteFile(path: path)
                // 캐쉬 제거
                removeCache(of: path)
            }
            
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> 삭제 중 에러 발생 = \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 파일 이동
    /// - Parameters:
    ///   - originPath: 원래 파일 경로.
    ///   - targetPath: 새로운 파일 경로.
    ///   - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///   - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러. 널값 지정 가능. 기본값은 널값.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    public func move(from originPath: String,
                     to targetPath: String,
                     conflictHandler: (@Sendable () async -> Files.Conflict)?,
                     _ progressHandler: ProgressHandler? = nil) async -> Result<Bool, any Error> {
        do {
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
                    progressHandler?(1, 1, 1, .move, originPath.lastPathComponent)
                    return .success(true)
                }
                
            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 이미 있는데 사용자 확인이 없습니다.")
                progressHandler?(1, 1, 1, .error(error), originPath.lastPathComponent)
                return .failure(error)
            }

            // 연결 개시
            let client = try await self.connect()

            try await client.move(from: originPath,
                                  to: targetPath)
            progressHandler?(1, 1, 1, .move, originPath.lastPathComponent)
            // 캐쉬 이동
            moveCache(from: originPath, to: targetPath)
            return .success(true)
        }
        catch {
            progressHandler?(1, 1, 1, .error(error), originPath.lastPathComponent)
            return .failure(error)
        }
    }
    
    /// 파일명 변경
    /// - Parameters:
    ///    - parentPath: 해당 파일이 속한 경로
    ///    - oldFilename: 원래 파일명
    ///    - newFilename: 새로운 파일명
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    public func rename(in parentPath: String,
                       from oldFilename: String,
                       to newFilename: String) async -> Result<Bool, any Error> {
        let originPath = parentPath.appendingPathComponent(oldFilename)
        let targetPath = parentPath.appendingPathComponent(newFilename)
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }
        
        do {
            // 연결 개시
            let client = try await self.connect()
            try await client.rename(from: originPath, to: targetPath)
            // 캐쉬 이동
            moveCache(from: originPath, to: targetPath)
            return .success(true)
        }
        catch {
            return .failure(error)
        }
    }
    
    // MARK: - Upload Methods
    /// 파일 업로드
    /// - Parameters:
    ///    - originPath: 업로드할 로컬 파일 경로.
    ///    - targetPath: 파일이 올라갈 FTP 경로, 업로드할 파일/폴더명까지 포함해야 한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    public func write(from originPath: String,
                      to targetPath: String,
                      conflictHandler: (@Sendable () async -> Files.Conflict)? = nil,
                      _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, any Error> {

        let filename = originPath.lastPathComponent

        do {
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
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 이미 있는데 사용자 확인이 없습니다.")
                progressHandler(1, 1, 1.0, .error(error), targetPath.lastPathComponent)
                return .failure(error)
            }

            // 연결 개시
            let client = try await self.connect()

            let url: URL
            if #available(macOS 13.0, *) {
                url = URL(filePath: originPath)
            }
            else {
                url = URL(fileURLWithPath: originPath)
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: originPath, isDirectory: &isDirectory) else {
                // 완료 처리
                progressHandler(1, 1, 1.0, .error(Files.Error.notExist), filename)
                // 파일이 존재하지 않음
                return .failure(Files.Error.notExist)
            }
            if isDirectory.boolValue == true {
                // 해당 위치에 디렉토리 생성
                try await client.createDirectory(path: targetPath)
                progressHandler(1, 1, 1.0, .write, targetPath.lastPathComponent)
            }
            else {
                // 취소 여부 확인
                try Task.checkCancellation()

                let fileSize = Int64(url.fileSize)
                try await client.upload(localPath: url, remotePath: targetPath) { completedFiles, fileBeingTransferred, bytesSent in
                    let fractionCompleted: Double = Double(bytesSent) / Double(fileSize)
                    progressHandler(fileSize, bytesSent, fractionCompleted, .write, filename)
                }
                // 완료 처리
                progressHandler(fileSize, fileSize, 1.0, .write, filename)
            }
            return .success(true)
        }
        catch {
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(error), filename)
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

        let filename = targetPath.lastPathComponent
        do {
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
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 파일이 이미 있는데 사용자 확인이 없습니다.")
                progressHandler(1, 1, 1.0, .error(error), targetPath.lastPathComponent)
                return .failure(error)
            }

            // 연결 개시
            let client = try await self.connect()

            // 취소 여부 확인
            try Task.checkCancellation()

            let fileSize = Int64(data.count)
            try await client.upload(content: data, path: targetPath) { progress in
                let progressed = Int64(Double(fileSize) * progress)
                let fractionCompleted: Double = Double(progressed) / Double(fileSize)
                progressHandler(fileSize, progressed, fractionCompleted, .write, filename)
            }
            // 완료 처리
            progressHandler(fileSize, fileSize, 1.0, .write, filename)
            return .success(true)
        }
        catch {
            // 완료 처리
            progressHandler(1, 1, 1.0, .error(error), filename)
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
        do {
            let client = try await self.connect()
            
            // 파일 존재 여부만 판별하기 위해, 에러 발생시 false 로 간주하도록 한다
            var isExist = false
            var isDirectory = false
            // 메쏘드 구조 상, 디렉토리 여부를 먼저 검사한다
            // `existFile(path:)` 메쏘드는 디렉토리도 파일로 간주하고, true를 반환하기 때문이다.
            if (try? await client.existDirectory(path: path)) ?? false {
                isExist = true
                isDirectory = true
            }
            else if (try? await client.existFile(path: path)) ?? false {
                isExist = true
            }
            
            guard isExist == true else {
                // 파일이 없기 때문에 덮어쓰기 불필요.
                return .success(true)
            }
            
            try Task.checkCancellation()

            guard let conflictHandler else {
                // 충돌 여부를 사용자에게 확인하지 않는 경우
                return .failure(Files.Error.disallowOverwrite)
            }

            // 확인 결과
            return await resolveFileConflict(isDirectory: isDirectory, conflictHandler) {
                // 사용자 덮어쓰기 승인 시
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 기존 파일을 제거합니다.")
                do {
                    // 해당 파일 제거
                    try await removeRecursvely(path, isDirectory: isDirectory)
                    return .success(true)
                }
                catch {
                    EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> 제거 중 에러 발생 = \(error.localizedDescription).")
                    return .failure(error)
                }
            }
        }
        catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> 에러 발생 = \(error.localizedDescription).")
            return .failure(error)
        }
    }
}

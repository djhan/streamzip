//
//  WebDAVFilesProvider.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/13/25.
//

import Foundation

import CommonLibrary
import FilesProvider

// MARK: - WebDav Provider Actor -
/// - WebDAV 파일 공급자
public actor WebDAVFilesProvider: HTTPProviderable {
    
    public typealias FileItem = WebDAVItem

    // MARK: - Properties
    /// baseURL
    public var baseURL: URL?
    /// URL Credential
    public var credential: URLCredential
    
    /// Session Delegate
    public var sessionDelegate: SessionDelegate<WebDAVFilesProvider>?
    /// Session
    public var _session: URLSession!
    
    /// URL Session Queue
    public var operationQueue = OperationQueue()

    public weak var urlCache: URLCache?
    
    /// 최대 동시 업로드 개수
    /// - WebDAV는 URLSession을 사용하므로 동시 연결을 잘 처리함
    public var maxConcurrentUploads: Int { 5 }
    /// E-Tag 또는 Revision identifier로 Cache Validating
    public var validatingCache: Bool = false

    /// 최대 업로드 사이즈
    public var maxUploadSize: Int64 {
        return Int64.max
    }

    // MARK: WebDAV
    let credentialType: URLRequest.AuthenticationType

    // MARK: - Deinitialization
    deinit {
        /// 세션 종료
        _session?.invalidateAndCancel()
        /// 캐쉬 제거 - 남겨두는 건 어떨까?
        // self.urlCache?.removeAllCachedResponses()
    }
    
    // MARK: - Initialization
    /// WebDAV 초기화
    /// - Parameters:
    ///   - baseURL: 기본 URL.
    ///   - credential: `URLCredential`. 사용자 명/비번 등을 포함한다.
    ///   - credentialType: URLRequest.AuthenticationType. 기본값은 nil이며, 이 경우 digest 방식으로 초기화된다.
    ///   - urlCache: 파일을 임시 저장할 수 있는 `URLCache` 지정. 기본값은 NIL.
    public init(_ baseURL: URL?,
                credential: URLCredential,
                credentialType: URLRequest.AuthenticationType? = nil,
                urlCache: URLCache? = nil) async {
        self.baseURL = baseURL
        self.credential = credential
        if let credentialType {
            self.credentialType = credentialType
        }
        else {
            self.credentialType = .digest
        }
        self.urlCache = urlCache
    }
    
    // MARK: - HTTP Providerable
    
    /// 접근 가능 여부
    public func canAccessible() async -> Result<Bool, Error> {
        var request = URLRequest(url: baseURL!)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(mimeType: .Xml, charset: .utf8)
        request.httpBody = WebDAVItem.xmlProp([.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let result = await self.doDataTask(with: request)
        switch result {
        case .success((let data, let response)):
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            if status >= 400 {
                if let code = HTTPErrorCode(rawValue: status) {
                    let errorDescription = String(data: data, encoding: .utf8)
                    let error = WebDavHTTPError(code: code, path: "", serverDescription: errorDescription, url: self.baseURL!)
                    return .failure(error)
                }
                else {
                    return .failure(Files.Error.connectToServerFailed)
                }
            }
            guard status < 300 else {
                // 서버 접근 실패 처리
                return .failure(Files.Error.connectToServerFailed)
            }
            // 접근 가능
            return .success(true)
            
        case .failure(let error):
            return .failure(error)
        }
    }

    /// 특정 작업의 Request 반환
    /// - Parameters:
    ///   - operation: `FileOperationType`
    ///   - overwrite: 덮어쓰기
    /// - Returns: `URLRequest`. 실패 시 널값 반환.
    public func request(for operation: FileOperationType,
                    overwrite: Bool = false) async -> URLRequest? {
        let method: String
        let url: URL
        let sourceURL = self.url(of: operation.source)
        
        switch operation {
        case .fetch:
            method = "GET"
            url = sourceURL
        case .create:
            if sourceURL.absoluteString.hasSuffix("/") {
                method = "MKCOL"
                url = sourceURL
            } else {
                fallthrough
            }
        case .modify:
            method = "PUT"
            url = sourceURL
            break
        case .copy(let source, let dest):
            if source.hasPrefix("file://") {
                method = "PUT"
                url = self.url(of: dest)
            } else if dest.hasPrefix("file://") {
                method = "GET"
                url = sourceURL
            } else {
                method = "COPY"
                url = sourceURL
            }
        case .move:
            method = "MOVE"
            url = sourceURL
        case .remove:
            method = "DELETE"
            url = sourceURL
        default:
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 정의되지 않은 작업 = \(operation.description)")
            return nil
            //fatalError("Unimplemented operation \(operation.description) in \(#file)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authentication: credential, with: credentialType)
        // Overwrite 헤더는 COPY, MOVE 작업에만 사용하도록 제한
        if ["COPY", "MOVE"].contains(method) {
            request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
        }
        if let dest = operation.destination, !dest.hasPrefix("file://") {
            request.setValue(self.url(of:dest).absoluteString, forHTTPHeaderField: "Destination")
        }
        
        return request
    }
    /// 데이터 업로드 작업의 Request 반환
    /// - Put 메쏘드는 덮어쓰기가 기본이다.
    /// - Parameters:
    ///   - destinationPath: 업로드 경로.
    ///   - overwrite: 덮어쓰기 여부.
    /// - Returns: `URLRequest`. 실패 시 널값 반환.
    public func requestForUploadData(to destinationPath: String) async -> URLRequest? {
        let url = self.url(of: destinationPath)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(url.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    /// 특정 경로의 아이템을 찾아서 반환
    /// - Parameter path: 상대 경로.
    /// - Returns: `FileItem` 또는 에러 반환.
    public func item(of path: String) async -> Result<WebDAVItem, Error> {
        return await self.item(path: path, attributes: [])
    }
    /// 특정 경로의 특정 키에 부합하는 아이템을 찾아서 반환
    /// - Parameters:
    ///   - path: 상대 경로.
    ///   - attributes: `URLResourceKey` 배열로 키 지정.
    /// - Returns: `FileItem` 또는 에러 반환.
    func item(path: String, attributes: [URLResourceKey]) async -> Result<WebDAVItem, Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }

        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(mimeType: .Xml, charset: .utf8)
        request.httpBody = WebDAVItem.xmlProp(attributes)
        let result = await doDataTask(with: request)
        switch result {
        case .success((let data, let urlResponse)):
            var responseError: HTTPError?
            if let code = (urlResponse as? HTTPURLResponse)?.statusCode, code >= 300 {
                if let rCode = HTTPErrorCode(rawValue: code) {
                    responseError = self.serverError(with: rCode, path: path, data: data)
                }
                else {
                    return .failure(Files.Error.notExist)
                }
            }
            let xresponse = WebDavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
            guard let response = xresponse.first else {
                return .failure(responseError ?? Files.Error.responseFailed)
            }
            return .success(WebDAVItem(response))

        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// 특정 상대 경로에 독립적으로 접근하기 위한 URL을 가져온다
    /// - OneDrive / WebDAV 여부에 따라 다른 로직을 실행한다.
    /// - Parameter path: 접근하려는 상대적 경로 지정.
    /// - Returns: `URL` 반환
    public func url(of path: String) -> URL {
        // 정규화 처리
        var realPath: String = path.precomposedStringWithCanonicalMapping
        realPath = realPath.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? realPath
        if let baseURL = baseURL {
            if realPath.hasPrefix("/") {
                realPath.remove(at: realPath.startIndex)
            }
            return URL(string: realPath, relativeTo: baseURL) ?? baseURL
        } else {
            return URL(string: realPath) ?? URL(string: "/")!
        }
    }
    /// 특정 URL의 상대적 경로 반환
    /// - Parameter url: `URL`
    /// - Returns: `String`으로 상대 경로 반환.
    public func relativePath(of url: URL) -> String {
        // 정규화 처리
        let relativePath = url.relativePath.precomposedStringWithCanonicalMapping
        if !relativePath.isEmpty, url.baseURL == self.baseURL {
            return (relativePath.removingPercentEncoding ?? relativePath).replacingOccurrences(of: "/", with: "", options: .anchored)
        }
        
        // resolve url string against baseurl
        guard let baseURL = self.baseURL else { return url.absoluteString }
        let standardRelativePath = url.absoluteString.replacingOccurrences(of: baseURL.absoluteString, with: "/").replacingOccurrences(of: "/", with: "", options: .anchored)
        if URLComponents(string: standardRelativePath)?.host?.isEmpty ?? true {
            return standardRelativePath.removingPercentEncoding ?? standardRelativePath
        } else {
            return relativePath.replacingOccurrences(of: "/", with: "", options: .anchored)
        }
    }
    
    // MARK: Return Error
    /// 서버 에러 반환
    /// - Parameters:
    ///   - code: `HTTPErrorCode`
    ///   - path: 경로. 널값 지정 가능.
    ///   - data: `Data`. 널값 지정 가능.
    /// - Returns: `HTTPError` 반환.
    public func serverError(with code: HTTPErrorCode, path: String?, data: Data?) -> HTTPError {
        return WebDavHTTPError(code: code,
                               path: path ?? "",
                               serverDescription: data.flatMap({ String(data: $0, encoding: .utf8) }),
                               url: self.url(of: path ?? ""))
    }
    /// 다중 Status 에러 반환
    /// - Parameters:
    ///   - operation: 작업 종류.
    ///   - data: response가 포함된 `Data`
    /// - Returns: HTTP 에러 반환.
    public func multiStatusError(operation: FileOperationType, data: Data) -> HTTPError? {
        let xresponses = WebDavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
        for xresponse in xresponses where (xresponse.status ?? 0) >= 300 {
            let code = xresponse.status.flatMap { HTTPErrorCode(rawValue: $0) } ?? .internalServerError
            return self.serverError(with: code, path: operation.source, data: data)
        }
        return nil
    }
    
    // MARK: - Listing Methods
    /// 특정 path 아래의 contents 아이템 목록을 `WebDAVItem` 배열로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    /// - Returns: `Result` 타입으로 `WebDAVItem` 배열 또는 에러 반환.
    public func contents(of path: String,
                         showHiddenFiles: Bool = false) async -> Result<[FileItem], Error> {

        return await self._searchFiles(path: path,
                                       showHiddenFiles: showHiddenFiles,
                                       recursive: false,
                                       query: nil,
                                       foundItemsHandler: nil) { _, _, _, _, _ in
            // 진행 상태 무시
        }
    }
    
    /// 재귀적 목록 생성 비동기 메쏘드
    /// - Parameters:
    ///     - path: 목록 생성 경로
    ///     - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    ///     - foundItemsHandler: 중간값 반환 핸들러.
    ///     - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    public func contentsOfDirectoryRecursively(path: String,
                                               showHiddenFiles: Bool = false,
                                               foundItemsHandler: ((_ contents: [FileItem]) -> Void)? = nil,
                                               _ progressHandler: @escaping ProgressHandler) async -> Result<[WebDAVItem], Error> {
        return await self._searchFiles(path: path,
                                       showHiddenFiles: showHiddenFiles,
                                       recursive: true,
                                       query: nil,
                                       foundItemsHandler: foundItemsHandler,
                                       progressHandler)
    }
    
    /// 기본 검색 비동기 메쏘드
    /// - Parameters:
    ///     - path: 검색할 경로
    ///     - showHiddenFiles: 감춤 파일 표시 여부. 기본값은 false
    ///     - recursive: 재귀적 검색 여부. true 로 지정하면 하위 폴더의 파일을 재귀적으로 계속 탐색한다. 기본값은 false.
    ///     - query: `NSPredicate`
    ///     - foundItemsHandler: 중간에 발견된 `FileItem` 배열
    ///     - progressHandler: 전체 개수, 진행 개수, 진행율, 진행 아이템명 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다. 진행율은 정확하게 파악된다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    public func searchFiles(path: String,
                            showHiddenFiles: Bool = false,
                            recursive: Bool = false,
                            query: NSPredicate,
                            foundItemsHandler: ((_ checkItems: [FileItem]) -> Void)?,
                            _ progressHandler: @escaping ProgressHandler) async -> Result<[FileItem], Error> {
        return await _searchFiles(path: path,
                                  showHiddenFiles: showHiddenFiles,
                                  recursive: recursive,
                                  query: query,
                                  foundItemsHandler: foundItemsHandler,
                                  progressHandler)
    }
    /// 기본 검색 비동기 내부 메쏘드
    /// - Parameters:
    ///     - path: 검색할 경로
    ///     - showHiddenFiles: 감춤 파일 표시 여부. 기본값은 false
    ///     - recursive: 재귀적 검색 여부. true 로 지정하면 하위 폴더의 파일을 재귀적으로 계속 탐색한다. 기본값은 false.
    ///     - query: `NSPredicate`, 널값으로 지정 가능. 널값 지정 시 검색을 실행하지 않게 되므로 주의한다.
    ///     - foundItemsHandler: 중간에 발견된 `FileItem` 배열
    ///     - progressHandler: 전체 개수, 진행 개수, 진행율, 진행 아이템명 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다. 진행율은 정확하게 파악된다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    private func _searchFiles(path: String,
                              showHiddenFiles: Bool = false,
                              recursive: Bool = false,
                              query: NSPredicate?,
                              foundItemsHandler: ((_ checkItems: [FileItem]) -> Void)?,
                              _ progressHandler: @escaping ProgressHandler) async -> Result<[FileItem], Error> {

        let url = self.url(of: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        // Depth infinity is disabled on some servers. Implement workaround?!
        request.setValue(recursive == true ? "infinity" : "1", forHTTPHeaderField: "Depth")
        request.setValue(authentication: credential, with: credentialType)
        request.setValue(mimeType: .Xml, charset: .utf8)
        request.httpBody = WebDAVItem.xmlProp([])

        var items = [WebDAVItem]()
        do {
            let result = await self.doDataTask(with: request)
            try Task.checkCancellation()
            
            switch result {
            case .success((let data, let response)):
                if let code = (response as? HTTPURLResponse)?.statusCode ,
                   code >= 300 {
                    // scope 종료 시
                    defer {
                        // 완료 핸들러 업데이트
                        progressHandler(1, 1, 1.0, .search, nil)
                    }
                    
                    //EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(response)")
                    if let rCode = HTTPErrorCode(rawValue: code) {
                        return .failure(self.serverError(with: rCode, path: path, data: data))
                    }
                    else {
                        return .failure(Files.Error.unknown)
                    }
                }
                
                let xresponse = WebDavResponse.parse(xmlResponse: data, baseURL: self.baseURL)
                
                var progressed: Int64 = 0
                let totalCount = Int64(xresponse.count)
                let fractionCompleted: Double = Double(progressed) / Double(totalCount)
                progressHandler(totalCount, progressed, fractionCompleted, .search, nil)
                
                let webDavItems: [FileItem] = xresponse.compactMap { attributes in
                    guard attributes.url.filePath != url.filePath else {
                        // 상위 경로와 동일한 경우 건너뛴다
                        progressed += 1
                        let fractionCompleted: Double = Double(progressed) / Double(totalCount)
                        progressHandler(totalCount, progressed, fractionCompleted, .search, nil)
                        return nil
                    }
                    let item = WebDAVItem(attributes)
                    
                    // scope 종료 시, 진행 상태 추가
                    defer {
                        progressed += 1
                        let fractionCompleted: Double = Double(progressed) / Double(totalCount)
                        progressHandler(totalCount, progressed, fractionCompleted, .search, item.filename)
                    }
                    
                    // 감춤 파일 추가 여부
                    if showHiddenFiles == false,
                       item.isHidden == true {
                        return nil
                    }
                    // 쿼리 검색 실행
                    if let query,
                       query.evaluate(with: item) == false {
                        return nil
                    }
                    // 중간값 반환
                    if let foundItemsHandler {
                        items.append(item)
                        foundItemsHandler(items)
                    }
                    return item
                }

                // 완료 핸들러 업데이트
                progressHandler(totalCount, totalCount, 1.0, .search, nil)
                return .success(webDavItems)
                
            case .failure(let error):
                // 완료 핸들러 업데이트
                progressHandler(1, 1, 1.0, .error(error), nil)
                return .failure(error)
            }
        }
        catch {
            return .failure(error)
        }
    }
    
    // MARK: - Operation Methods

    /// 특정 `WebDAVItem` 제거
    /// - Parameters:
    ///    - item: 제거할 `WebDAVItem`
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(_ item: WebDAVItem) async -> Result<Bool, any Error> {
        return await doOperation(.remove(path: item.path.precomposedStringWithCanonicalMapping))
    }
    /// 특정 경로의 파일 제거
    /// - Parameters:
    ///    - path: 제거할 파일 경로.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(of path: String) async -> Result<Bool, Error> {
        return await doOperation(.remove(path: path.precomposedStringWithCanonicalMapping))
    }

    /// 파일 이동
    /// - Parameters:
    ///   - originPath: 원래 파일 경로.
    ///   - targetPath: 새로운 파일 경로.
    ///   - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///   - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러. 널값 지정 가능. 기본값은 널값이다.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    public func move(from originPath: String,
                     to targetPath: String,
                     conflictHandler: (@Sendable () async -> Files.Conflict)?,
                     _ progressHandler: ProgressHandler? = nil) async -> Result<Bool, any Error> {
        let originPath = originPath.precomposedStringWithCanonicalMapping
        let targetPath = targetPath.precomposedStringWithCanonicalMapping
        
        defer {
            progressHandler?(1, 1, 1, .move, originPath.lastPathComponent)
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
                return .success(true)
            }
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(targetPath) >> 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
        
        return await doOperation(.move(source: originPath,
                                       destination: targetPath))
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
        let originPath = parentPath.appendingPathComponent(oldFilename).precomposedStringWithCanonicalMapping
        let targetPath = parentPath.appendingPathComponent(newFilename).precomposedStringWithCanonicalMapping
        return await doOperation(.move(source: originPath, destination: targetPath))
    }
}

// MARK: - WebDav HTTP Error
struct WebDavHTTPError: HTTPError {
    /// 에러 코드
    public let code: HTTPErrorCode
    /// 경로
    public let path: String
    /// 서버 설명
    public let serverDescription: String?
    /// URL 또는 에러를 발생시킨 리소스
    public let url: URL
}

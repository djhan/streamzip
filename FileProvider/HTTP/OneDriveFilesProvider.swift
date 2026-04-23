//
//  OneDriveFilesProvider.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/13/25.
//

import Foundation

import CommonLibrary
/// OAuthSwift 에서 MSAL로 변경
import MSAL
//internal import OAuthSwift

// MARK: - MSALPublicClientApplication Extension -
/// MSALPublicClientApplication 를 Sendable 로 확장
extension MSALPublicClientApplication: @unchecked @retroactive Sendable {
    
}

// MARK: - OneDrive Provider Actor -
/// - OneDrive 파일 공급자
public actor OneDriveFilesProvider: HTTPProviderable {
    
    // MARK: - Enumeration
    /// OneDrive 파일 컨테이너 접근용 Route
    /// - 기본 로그인 사용자로는 `.me`를 사용한다.
    /// 그렇지 않은 경우 드라이브 ID, 그룹 ID, 사이트 ID 또는 다른 사용자의 기본 컨테이너 사용자 ID를 기반으로 컨테이너에 접근할 수 있다.
    public enum Route: RawRepresentable {
        /// Access to default container for current user
        case me
        /// Access to a specific drive by id
        case drive(uuid: UUID)
        /// Access to a default drive of a group by their id
        case group(uuid: UUID)
        /// Access to a default drive of a site by their id
        case site(uuid: UUID)
        /// Access to a default drive of a user by their id
        case user(uuid: UUID)
        
        // MARK: Initialization
        public init?(rawValue: String) {
            let components = rawValue.components(separatedBy: ";")
            guard let type = components.first else {
                return nil
            }
            if type == "me" {
                self = .me
            }
            guard let uuid = components.last.flatMap({ UUID(uuidString: $0) }) else {
                return nil
            }
            switch type {
            case "drive":
                self = .drive(uuid: uuid)
            case "group":
                self = .group(uuid: uuid)
            case "site":
                self = .site(uuid: uuid)
            case "user":
                self = .user(uuid: uuid)
            default:
                return nil
            }
        }
        // MARK: RawValue (String)
        public var rawValue: String {
            switch self {
            case .me:
                return "me;"
            case .drive(uuid: let uuid):
                return "drive;" + uuid.uuidString
            case .group(uuid: let uuid):
                return "group;" + uuid.uuidString
            case .site(uuid: let uuid):
                return "site;" + uuid.uuidString
            case .user(uuid: let uuid):
                return "user;" + uuid.uuidString
            }
        }
        // MARK: Drive Path
        /// 선택 드라이브의 URL 경로를 반환
        var drivePath: String {
            switch self {
                case .me:
                return "me/drive"
                case .drive(uuid: let uuid):
                return "drives/" + uuid.uuidString
                case .group(uuid: let uuid):
                return "groups/" + uuid.uuidString + "/drive"
                case .site(uuid: let uuid):
                return "sites/" + uuid.uuidString + "/drive"
                case .user(uuid: let uuid):
                return "users/" + uuid.uuidString + "/drive"
            }
        }
    }

    // MARK: - Static Properties
    
    /// Microsoft Graph URL
    static let graphURL = URL(string: "https://graph.microsoft.com/")!
    
    /// Microsoft Graph URL
    static let graphVersion = "v1.0"
        
    // MARK: - Properties
    
    public typealias FileItem = OneDriveItem

    /// baseURL
    public var baseURL: URL?
    /// URL Credential
    public var credential: URLCredential
    
    /// Session Delegate
    public var sessionDelegate: SessionDelegate<OneDriveFilesProvider>?
    /// Session
    public var _session: URLSession!
    
    /// URL Session Queue
    public var operationQueue = OperationQueue()

    public weak var urlCache: URLCache?
    /// E-Tag 또는 Revision identifier로 Cache Validating
    public var validatingCache: Bool = false

    /// 최대 업로드 사이즈
    public var maxUploadSize: Int64 {
        /// 4MB로 제한
        return 4_194_304
    }

    /// 최대 동시 업로드 개수
    /// - OneDrive는 URLSession을 사용하므로 동시 연결을 잘 처리함
    public var maxConcurrentUploads: Int { 5 }


    /// 연결 Task
    private var connectionTask: Task<Void, Never>?
    
    // MARK: OneDrive
    /// Route
    let route: OneDriveFilesProvider.Route
    
    /// MSAL로 대체
    /// OAuth2Swift
    //internal var oauth: OAuth2Swift
    
    /// MSAL 어플리케이션 프로퍼티
    var application: MSALPublicClientApplication?
    /// MSAL 대응 ViewController
    /// - Important: 초기화 후, `setupParentViewController(:_)`메쏘드로 필요할 때마다 지정한다.
#if os(macOS)
    private var parentViewController: NSViewController?
#elseif os(iOS)
    private var parentViewController: UIViewController?
#endif
    // Cloud Configuration
    // 인증에 필요한 설정
    var configuration: CloudConfiguration

    // MARK: - Deinitialization
    deinit {
        /// 세션 종료
        _session?.invalidateAndCancel()
        /// 재연결 작업 종료
        connectionTask?.cancel()
    }
    
    // MARK: - Initialization
    /// OneDrive 초기화
    /// - Parameters:
    ///   - serverURL: 원드라이브 비즈니스 서버 사용 시 지정되는 URL. 기본값은 널값이며, 일반 유저라면 널값으로 지정한다.
    ///   - appID: 인증에 필요한 AppID.
    ///   - redirectPath: Xcode의 `Info>URL`에 등록된 값을 입력한다. 즉, `msauth.com.djhan.EdgeFileProvider` 같은 형식이다. 맨 뒤에 `://auth`는 여기서 초기화하면서 자동으로 추가한다.
    ///   - route: `OneDriveFileProvider.Route`. 기본값은 me.
    ///   - urlCache: 파일을 임시 저장할 수 있는 `URLCache` 지정. 기본값은 널값.
    public init(_ serverURL: URL? = nil,
                appId: String,
                redirectPath: String,
                route: OneDriveFilesProvider.Route = .me,
                urlCache: URLCache? = nil) throws {
        
        let baseURL = (serverURL?.absoluteURL ?? Self.graphURL).appendingPathComponent(Self.graphVersion, isDirectory: true)
        let refinedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.baseURL = refinedBaseURL
        
        // credential은 더미 값으로 초기화
        self.credential = URLCredential()
        self.route = route
        self.urlCache = urlCache
        self.configuration = CloudConfiguration(host: CloudInformation.Host.oneDrive.rawValue,
                                                tokenLabel: CloudInformation.TokenLabel.oneDrive.rawValue,
                                                apiHost: CloudInformation.APIHost.oneDrive.rawValue,
                                                appId: appId,
                                                appSecret: "",
                                                redirectPath: redirectPath + "://auth",
                                                authorizePath: "https://login.microsoftonline.com/common",
                                                //authorizePath: "https://login.live.com/oauth20_authorize.srf",
                                                //accessTokenPath: "https://login.live.com/oauth20_token.srf",
                                                responseType: "code",
                                                scopes: ["User.Read", "Files.ReadWrite.All"])
        
        do {
            let authority = try MSALAADAuthority(url: self.configuration.authorizeURL)
            let config = MSALPublicClientApplicationConfig(clientId: self.configuration.appId,
                                                           redirectUri: self.configuration.redirectPath,
                                                           authority: authority)
            self.application = try MSALPublicClientApplication(configuration: config)
        } catch {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: MSAL authority creation failed: error=\(error as NSError) userInfo=\((error as NSError).userInfo)")
            throw error
        }
        
  /// MSAL로 대체
//        self.oauth = OAuth2Swift.init(consumerKey: configuration.appId,
//                                      consumerSecret: configuration.appSecret,
//                                      authorizeUrl: configuration.authorizeUrl,
//                                      accessTokenUrl: configuration.accessTokeUrl,
//                                      responseType: configuration.responseType)
    }
#if os(macOS)
    /// Parent ViewController 지정
    public func setupParentViewController(_ viewController: NSViewController) {
        self.parentViewController = viewController
    }
#elseif os(iOS)
    /// Parent ViewController 지정
    public func setupParentViewController(_ viewController: UIViewController) {
        self.parentViewController = viewController
    }
#endif

    // MARK: - Authorize
    /// 연결 실행
    /// - 접속 가능 여부를 테스트한 다음, 필요하다면 인증을 진행하고 그 결과를 반환한다.
    /// - Returns: Result 타입으로 성공 시 true, 실패 시 에러 반환.
    public func connect() async -> Result<Bool, Error> {
        guard self.configuration.token == nil else {
            // 이미 접속 가능 상태
            return .success(true)
        }
        
        // scope 종료 시
        defer {
            // 기존 작업 취소
            connectionTask?.cancel()
            // 59분 간격으로 작동하는 재접속 Task를 등록한다
            connectionTask = Task {
                while !Task.isCancelled {
                    do {
                        // 59분 직접 대기 (1초마다 폴링 불필요)
                        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                            // macOS 13 이상: Duration 기반의 최신 API 사용
                            try await Task.sleep(for: .seconds(60 * 59))
                        } else {
                            // macOS 13 미만: 나노초(Nanoseconds) 기반의 이전 API 사용
                            // 1초 = 1,000,000,000 나노초
                            let nanoseconds = UInt64(60 * 59) * 1_000_000_000
                            try await Task.sleep(nanoseconds: nanoseconds)
                        }
                    } catch {
                        // Task 취소 시 CancellationError 발생 → 즉시 종료
                        break
                    }

                    guard !Task.isCancelled else { break }

                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 59분 경과, 재접속을 실행합니다.")
                    // 재연결 실행
                    let result = await _connect()
                    switch result {
                        // 성공 시 — 다음 루프에서 다시 59분 대기
                    case .success:
                        break
                        // 에러 발생 시
                    case .failure(let error):
                        EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 재연결에 실패했습니다. 에러 = \(error.localizedDescription).")
                        // 토큰 초기화
                        self.configuration.token = nil
                        // Task 즉시 종료
                        return
                    }
                }

                // 재연결 취소
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 재연결 작업을 취소하고 작업을 종료합니다.")
            }
        }
        
        // 토큰이 없는 경우 접속 실행
        return await _connect()
    }
    /// 연결 실행 private 메쏘드
    /// - 접속 가능 여부를 테스트한 다음, 필요하다면 인증을 진행하고 그 결과를 반환한다.
    /// - Returns: Result 타입으로 성공 시 true, 실패 시 에러 반환.
    private func _connect() async -> Result<Bool, Error> {

        let scopes = self.configuration.scopes ?? ["User.Read"]

        // 접근 불가능 시, authorize 진행
        // 1. 먼저 Silent 시도
        let result = await connectSilently()
        
        guard case .success(let token) = result else {
            // 3. 실패한 경우 직접 인증 시도
            switch await connectInteractively() {
                // 성공 시
            case .success(let token):
                self.configuration.token = token
                return .success(true)
                // 실패 시
            case .failure(let error):
                return .failure(error)
            }
        }
        
        self.configuration.token = token
        // 성공 시
        return .success(true)
        
        /// 키체인 또는 토큰 리프레쉬 시도 내부 메쏘드
        func connectSilently() async -> Result<String, Error> {
            guard let application else {
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: application 또는 parentViewController 정보가 없음.")
                return .failure(Files.Error.insufficientInformation)
            }

            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 키체인 토큰 확인.")
            do {
                let accounts = try application.allAccounts()
                guard let account = accounts.first else {
                    throw Files.Error.keychainFailed
                }
                
                let silentParams = MSALSilentTokenParameters(scopes: scopes, account: account)
                let result = try await application.acquireTokenSilent(with: silentParams)
                return .success(result.accessToken)
            } catch {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: error : \(error)")
                return .failure(error)
            }
        }
        
        /// 직접 인증 시도용 내부 메쏘드
        /// - Returns: Result 타입으로 `String` 토큰값 또는 에러값 반환.
        func connectInteractively() async -> Result<String, Error> {
            guard let application,
                  let parentViewController else {
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: application 또는 parentViewController 정보가 없음.")
                return .failure(Files.Error.insufficientInformation)
            }

            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자 직접 로그인을 시도.")
            let webParameters = MSALWebviewParameters(authPresentationViewController: parentViewController)

            // Filter out reserved scopes that MSAL disallows in interactive calls
            let reserved: Set<String> = ["openid", "profile", "offline_access"]
            var interactiveScopes = scopes.filter { !reserved.contains($0.lowercased()) }
            if interactiveScopes.isEmpty {
                // Ensure at least a sane default scope
                interactiveScopes = ["User.Read"]
            }

            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: Starting interactive MSAL acquire token; redirect=\(self.configuration.redirectPath), requestedScopes=\(scopes), interactiveScopes=\(interactiveScopes)")

            let interactiveParameters = MSALInteractiveTokenParameters(scopes: interactiveScopes,
                                                                       webviewParameters: webParameters)
            // 메인 쓰레드로 실행
            let task = Task<String, Error> { @MainActor in
                do{
                    let result = try await application.acquireToken(with: interactiveParameters)
                    return result.accessToken
                }
            }
            
            do {
                let token = try await task.value
                return .success(token)
            } catch {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: error : \(error)")
                return .failure(error)
            }
        }
        
//        let result = await self.authorize()
//        switch result {
//            // 인증 성공 시
//        case .success(_): return .success(true)
//            // 인증 실패 시
//        case .failure(let error): return .failure(error)
//        }
    }
        
    // MARK: - HTTP Providerable
        
    /// 접근 가능 여부
    /// - Returns: Result 타입으로 성공 시 true 반환. 실패 시 에러 반환.
    public func canAccessible() async -> Result<Bool, Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }
        guard let token = configuration.token else {
            return .failure(Files.Error.tokenFailed)
        }
        var request = URLRequest(url: self.url(of: ""))
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        //request.setValue(authentication: credential, with: .oAuth2)
        let result = await self.doDataTask(with: request)
        switch result {
        case .success((let data, let response)):
            let status = (response as? HTTPURLResponse)?.statusCode ?? 400
            if status >= 400 {
                if let code = HTTPErrorCode(rawValue: status) {
                    let errorDescription = String(data: data, encoding: .utf8)
                    let error = OneDriveHTTPError(code: code, path: "", serverDescription: errorDescription)
                    return .failure(error)
                }
                else {
                    return .failure(Files.Error.unknown)
                }
            }
            guard status == 200 else {
                /// 서버 접속 실패 에러
                return .failure(Files.Error.connectToServerFailed)
            }
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
        
        /// 경로 수정용 내부 메쏘드
        func correctPath(_ path: String) -> String {
            if path.hasPrefix("id:") {
                return path
            }
            var p = path.hasPrefix("/") ? path : "/" + path
            if p.hasSuffix("/") {
                p.remove(at: p.index(before:p.endIndex))
            }
            return p
        }
        
        // 접속 확인
        let connected = await self.connect()
        switch connected {
        case .failure(_):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 접속 실패!")
            return nil
        default: break
        }
        
        guard let token = configuration.token else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 토큰 없음!")
            return nil
        }
        
        let method: String
        let url: URL
        switch operation {
        case .fetch(path: let path):
            method = "GET"
            url = self.url(of: path, modifier: "content")
        case .create(path: let path) where path.hasSuffix("/"):
            method = "POST"
            let parent = path.deletingLastPathComponent()
            url = self.url(of: parent, modifier: "children")
        case .modify(path: let path):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = URL(string: self.url(of: path, modifier: "content").absoluteString + queryStr)!
        case .copy(source: let source, destination: let dest) where source.hasPrefix("file://"):
            method = "PUT"
            let queryStr = overwrite ? "" : "?@name.conflictBehavior=fail"
            url = URL(string: self.url(of: dest, modifier: "content").absoluteString + queryStr)!
        case .copy(source: let source, destination: let dest) where dest.hasPrefix("file://"):
            method = "GET"
            url = self.url(of: source, modifier: "content")
        case .copy(source: let source, destination: _):
            method = "POST"
            url = self.url(of: source, modifier: "copy")
        case .move(source: let source, destination: _):
            method = "PATCH"
            url = self.url(of: source)
        case .remove(path: let path):
            method = "DELETE"
            url = self.url(of: path)
        default:
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 정의되지 않은 작업 = \(operation.description)")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        //request.setValue(authentication: self.credential, with: .oAuth2)
        // Remove gzip to fix availability of progress re. (Oleg Marchik)[https://github.com/evilutioner] PR (#61)
        if method == "GET" {
            request.setValue(acceptEncoding: .deflate)
            request.addValue(acceptEncoding: .identity)
        }
        
        switch operation {
        case .create(path: let path) where path.hasSuffix("/"):
            request.setValue(mimeType: .Json)
            var requestDictionary = [String: Any]()
            let name = path.lastPathComponent
            requestDictionary["name"] = name
            requestDictionary["folder"] = [String: Any]()
            requestDictionary["@microsoft.graph.conflictBehavior"] = "fail"
            request.httpBody = Data(jsonDictionary: requestDictionary)
        case .copy(let source, let dest) where !source.hasPrefix("file://") && !dest.hasPrefix("file://"),
             .move(source: let source, destination: let dest):
            request.setValue(mimeType: .Json, charset: .utf8)
            let cdest = correctPath(dest)
            var parentReference: [String: Any] = [:]
            if cdest.hasPrefix("id:") {
                parentReference["id"] = cdest.components(separatedBy: "/").first?.replacingOccurrences(of: "id:", with: "", options: .anchored)
            } else {
                parentReference["path"] = "/drive/root:".appendingPathComponent(cdest.deletingLastPathComponent())
            }
            switch self.route {
            case .drive(uuid: let uuid):
                parentReference["driveId"] = uuid.uuidString
            default:
                //parentReference["driveId"] = cachedDriveID ?? ""
                break
            }
            var requestDictionary = [String: Any]()
            requestDictionary["parentReference"] = parentReference
            requestDictionary["name"] = cdest.lastPathComponent
            request.httpBody = Data(jsonDictionary: requestDictionary)
        default:
            break
        }
        
        return request
    }

    /// 특정 경로의 아이템을 찾아서 반환
    /// - Parameter path: 상대 경로.
    /// - Returns: `FileItem` 또는 에러 반환.
    public func item(of path: String) async -> Result<OneDriveItem, Error> {
        // 접속 확인
        let connected = await self.connect()
        switch connected {
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 접속 실패!")
            return .failure(error)
        default: break
        }

        guard let token = configuration.token else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 토큰 없음!")
            return .failure(Files.Error.tokenFailed)
        }

        var request = URLRequest(url: url(of: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        //request.setValue(authentication: self.credential, with: .oAuth2)
        let result = await doDataTask(with: request)
        switch result {
        case .success((let data, let urlResponse)):
            var responseError: HTTPError?
            if let code = (urlResponse as? HTTPURLResponse)?.statusCode, code >= 400,
                let rCode = HTTPErrorCode(rawValue: code) {
                responseError = self.serverError(with: rCode, path: path, data: data)
            }
            guard let baseURL,
               let json = data.deserializeJSON(),
               let oneDriveItem = OneDriveItem(baseURL: baseURL, route: self.route, json: json) else {
                return .failure(responseError ?? Files.Error.makeFileItemFailed)
            }
            return .success(oneDriveItem)
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// 특정 상대 경로에 독립적으로 접근하기 위한 URL을 가져온다
    /// - OneDrive / WebDAV 여부에 따라 다른 로직을 실행한다.
    /// - Parameter path: 접근하려는 상대적 경로 지정.
    /// - Returns: `URL` 반환
    public func url(of path: String) -> URL {
        // 경로 정규화 처리
        let path = path.precomposedStringWithCanonicalMapping
        return OneDriveItem.url(of: path, modifier: nil, baseURL: baseURL!, route: self.route)
    }
    /// 특정 상대 경로에 독립적으로 접근하기 위한 URL을 가져온다
    /// - OneDrive / WebDAV 여부에 따라 다른 로직을 실행한다.
    /// - Parameters
    ///     - path: 접근하려는 상대적 경로 지정.
    ///     - modifier: 사용 용도를 지정하는 스트링으로 경로 뒤에 붙인다. e.g. `contents` 등.
    /// - Returns: `URL` 반환
    func url(of path: String, modifier: String? = nil) -> URL {
        // 경로 정규화 처리
        let path = path.precomposedStringWithCanonicalMapping
        return OneDriveItem.url(of: path, modifier: modifier, baseURL: baseURL!, route: self.route)
    }
    /// 특정 URL의 상대적 경로 반환
    /// - Parameter url: `URL`
    /// - Returns: `String`으로 상대 경로 반환.
    public func relativePath(of url: URL) -> String {
        return OneDriveItem.relativePath(of: url, baseURL: baseURL, route: self.route)
    }
    
    /// 데이터 업로드 작업의 Request 반환
    /// - Parameters:
    ///   - destinationPath: 업로드 경로.
    /// - Returns: `URLRequest`. 실패 시 널값 반환.
    public func requestForUploadData(to destinationPath: String) async -> URLRequest? {
        let operation = FileOperationType.copy(source: "file://", destination: destinationPath)
        var request = await self.request(for: operation)
        request?.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - Listing Methods
    
    /// 특정 path 아래의 contents 아이템 목록을 `OneDriveItem` 배열로 반환
    /// - Parameters:
    ///    - 파일 경로를 지정한다.
    ///    - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    /// - Returns: `Result` 타입으로 `OneDriveItem` 배열 또는 에러 반환.
    public func contents(of path: String,
                         showHiddenFiles: Bool) async -> Result<[OneDriveItem], any Error> {
        guard let baseURL = self.baseURL else {
            return .failure(Files.Error.noServer)
        }
        
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(#file) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }

        // 접속 확인
        let connected = await self.connect()
        switch connected {
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 접속 실패!")
            return .failure(error)
        default: break
        }
        
        guard let token = configuration.token else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 토큰 없음!")
            return .failure(Files.Error.tokenFailed)
        }

        return await self.paginated(path) { newToken in
            let url = newToken.flatMap(URL.init(string:)) ?? self.url(of: path, modifier: "children")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        } pageHandler: { data in
            guard let json = data?.deserializeJSON(), let entries = json["value"] as? [Any] else {
                let err = URLError(.badServerResponse, url:  self.url(of: path))
                return ([], err, nil)
            }
            
            var files = [OneDriveItem]()
            for entry in entries {
                if let entry = entry as? [String: Any],
                    let file = OneDriveItem(baseURL: baseURL, route: self.route, json: entry, showHiddenFile: showHiddenFiles) {
                    files.append(file)
                }
            }
            return (files, nil, json["@odata.nextLink"] as? String)
        }
    }
    
    // MARK: - Operation Methods
    
    /// 특정 `OneDriveItem` 제거
    /// - Parameters:
    ///    - item: 제거할 `OneDriveItem`
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(_ item: OneDriveItem) async -> Result<Bool, any Error> {
        return await _doOperation(.remove(path: item.path.precomposedStringWithCanonicalMapping))
    }
    /// 특정 경로의 파일 제거
    /// - Parameters:
    ///    - path: 제거할 파일 경로.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func remove(of path: String) async -> Result<Bool, Error> {
        return await _doOperation(.remove(path: path.precomposedStringWithCanonicalMapping))
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

        return await _doOperation(.move(source: originPath.precomposedStringWithCanonicalMapping,
                                        destination: targetPath.precomposedStringWithCanonicalMapping))
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
        return await _doOperation(.move(source: originPath, destination: targetPath))
    }
    
    /// doOperation 실행 메쏘드
    /// - Important: `OneDriveFileProvider` 내부에서는 `doOperation()` 대신 이 메쏘드를 사용해야 한다.
    /// 왜냐하면 접속 여부 및 접속까지 완료한 다음, `doOperation()` 을 실행해야 하기 때문이다.
    private func _doOperation(_ operation: FileOperationType,
                              overwrite: Bool = false) async -> Result<Bool, any Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }

        // 접속 확인
        let connected = await self.connect()
        switch connected {
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(#file) >> 접속 실패!")
            return .failure(error)
        default: break
        }
        
        return await doOperation(operation, overwrite: overwrite)
    }
    
    // MARK: - Return Error
    /// 서버 에러 반환
    /// - Parameters:
    ///   - code: `HTTPErrorCode`
    ///   - path: 경로. 널값 지정 가능.
    ///   - data: response가 포함된 `Data`. 널값 지정 가능.
    /// - Returns: `HTTPError` 반환.
    public func serverError(with code: HTTPErrorCode, path: String?, data: Data?) -> HTTPError {
        let errorDescription: String?
        if let response = data?.deserializeJSON() {
            errorDescription = (response["error"] as? [String: Any])?["message"] as? String
        } else {
            errorDescription = data.flatMap({ String(data: $0, encoding: .utf8) })
        }
        return OneDriveHTTPError(code: code, path: path ?? "", serverDescription: errorDescription)
    }
    /// 다중 Status 에러 반환
    /// - Parameters:
    ///   - operation: 작업 종류.
    ///   - data: response가 포함된 `Data`
    /// - Returns: HTTP 에러 반환.
    public func multiStatusError(operation: FileOperationType, data: Data) -> HTTPError? {
        // 사용하지 않음
        return nil
    }
}

// MARK: - OneDrive HTTP Error
public struct OneDriveHTTPError: HTTPError {
    /// 에러 코드
    public let code: HTTPErrorCode
    /// 경로
    public let path: String
    /// 서버 설명
    public let serverDescription: String?
}


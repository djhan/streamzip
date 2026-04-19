//
//  OAuthorizable.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 12/2/25.
//

import Foundation

internal import OAuthSwift
import CommonLibrary

// MARK: - OAuth Authorizable Protocol -
/// OAuthSwift 로 인증을 처리하는 Actor 프로토콜
/// - Important: OneDrive 등 OAuthSwift 인증이 필요한 Actor는 이 프로토콜을 상속한다.
protocol OAuthorizable: Actor {
    /// OAuthSwift 오브젝트
    var oauth: OAuth2Swift { get set }
    /// OAuth 인증용 configuration
    var configuration: CloudConfiguration { get }
    /// OAuth 인증된 `URLCredential`
    var credential: URLCredential { get set }
    
    /// 접근 가능 여부
    func canAccessible() async -> Result<Bool, Error>
}

extension OAuthorizable {
    
// MARK: - OAuth Authorization

#if os(macOS)
    /// OAuth인증 작업 후 OneDrive File Credential 생성
    /// - Returns: completionHandler 로 'URLCredential' 또는 에러 반환.
    /// - Important: 1차적으로 키체인에서 복원 시도. 복원이 실패하면 처음부터 다시 인증을 받는다.
    /// 단, [참고 링크](https://github.com/amosavian/FileProvider/blob/master/Docs/OAuth.md) 에 따르면 1시간마다 토큰이 무효화되기 때문에 완료 핸들러에서 에러 발생시 이를 갱신할 필요가 있다고 한다.
    func authorize() async -> Result<URLCredential, Error> {
        // 키체인에 저장된 토큰 복원 시도
        let restoreTokenResult = self.restoreToken()
        // 토큰 복원 성공 여부 확인
        switch restoreTokenResult {
        case .success(let restoredToken):
            // 토큰 리프레시 시도
            let refreshResult = await self.refreshToken(restoredToken)
            switch refreshResult {
            case .success(let refreshedToken):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 리프레시된 토큰에서 credential 재생성 시도.")
                // 리프레시된 토큰으로 credential 생성. 키체인 토큰을 다시 저장하지는 않는다.
                self.credential = self.makeCredential(refreshedToken)
                // 접근 가능 여부 확인
                let accessible = await self.canAccessible()
                switch accessible {
                case .success(_):
                    // 접근 가능 시
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 복원된 토큰에서 재생성된 credential 로 접근 성공.")
                    return .success(credential)
                case .failure(let error):
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 접속 불가. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
                }

            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 복원된 토큰 refresh 실패. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
            }
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 복원 실패. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
        }
        
        // 재인증 절차가 필요한 경우
        // 재인증 실행
        let result = await self.authorize(scope: configuration.scopes?.joined(separator: " ") ?? "",
                                          state: "")
        switch result {
        case .success(let token):
            // self.credential 에 새로운 credential 대입. 키체인에 토큰을 저장한다.
            self.credential = self.makeCredential(token, saveToken: true)
            // 저장 완료 후 credential 반환
            return .success(credential)
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 실패. 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
    }
#elseif os(iOS)
    /// OAuth인증 작업 후 OneDrive File Credential 생성
    /// - Parameter urlHandler: `SafariURLHandler`로 기본값은 널값.
    /// - Returns: completionHandler 로 'URLCredential' 또는 에러 반환.
    /// - Important: 1차적으로 키체인에서 복원 시도. 복원이 실패하면 처음부터 다시 인증을 받는다.
    /// 단, [참고 링크](https://github.com/amosavian/FileProvider/blob/master/Docs/OAuth.md) 에 따르면 1시간마다 토큰이 무효화되기 때문에 완료 핸들러에서 에러 발생시 이를 갱신할 필요가 있다고 한다.
    func authorize(_ urlHandler: SafariURLHandler? = nil) async -> Result<URLCredential, Error> {
        // urlHandler 가 있는 경우, 지정
        if let urlHandler {
            oauth.authorizeURLHandler = urlHandler
        }
        // 키체인에 저장된 토큰 복원 시도
        let restoreTokenResult = self.restoreToken()
        // 토큰 복원 성공 여부 확인
        switch restoreTokenResult {
        case .success(let restoredToken):
            // 토큰 리프레시 시도
            let refreshResult = await self.refreshToken(restoredToken)
            switch refreshResult {
            case .success(let refreshedToken):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 리프레시된 토큰에서 credential 재생성 시도.")
                // 리프레시된 토큰으로 credential 생성. 키체인 토큰을 다시 저장하지는 않는다.
                self.credential = self.makeCredential(refreshedToken)
                // 접근 가능 여부 확인
                let accessible = await self.canAccessible()
                switch accessible {
                case .success(_):
                    // 접근 가능 시
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 복원된 토큰에서 재생성된 credential 로 접근 성공.")
                    return .success(credential)
                case .failure(let error):
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 접속 불가. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
                }

            case .failure(let error):
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 복원된 토큰 refresh 실패. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
            }
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 복원 실패. 재인증 절차를 밟는다. 에러 = \(error.localizedDescription)")
        }
        
        // 재인증 절차가 필요한 경우
        // 재인증 실행
        let result = await self.authorize(scope: configuration.scopes?.joined(separator: " ") ?? "",
                                          state: "")
        switch result {
        case .success(let token):
            // self.credential 에 새로운 credential 대입. 키체인에 토큰을 저장한다.
            self.credential = self.makeCredential(token, saveToken: true)
            // 저장 완료 후 credential 반환
            return .success(credential)
            
        case .failure(let error):
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 실패. 에러 발생 = \(error.localizedDescription)")
            return .failure(error)
        }
    }
#endif
    
    /// OAUTH 실제 인증 메쏘드
    /// - Parameters:
    ///   - scope: 스콥 범위.
    ///   - state: 상태 지정.
    /// - Returns: Result 타입으로 토큰 스트링, 또는 에러 반환.
    private func authorize(scope: String,
                           state: String) async -> Result<String, Error> {
        oauth.allowMissingStateCheck = true
        return await withCheckedContinuation { continuation in
            oauth.authorize(withCallbackURL: URL.init(string: configuration.redirectPath),
                            scope: scope,
                            state: state) { result in
                switch result {
                //case .success(let (credential, response, parameters)):
                case .success(let (credential, _, _)):
                    continuation.resume(returning: .success(credential.oauthToken))
                case .failure(let error):
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
    
    /// 특정 token 기반으로 credential을 생성해 반환
    /// - Important: 키체인에 토큰을 저장하려면 saveToken 패러미터를 true로 지정한다.
    /// - Parameters:
    ///   - oauthToken: 토큰 값.
    ///   - saveToken: 토큰을 키체인에 저장할지 여부. 기본값은 false.
    ///   - port: 기본값은 80.
    ///   - protocol: 기본값은 http.
    ///   - realm: 기본값은 Restricted
    ///   - authenticationMethod: 기본값은 `NSURLAuthenticationMethodHTTPBasic`.
    private func makeCredential(_ oauthToken: String,
                                saveToken: Bool = false,
                                port: Int = 80,
                                protocolType: String = "hhtp",
                                realm: String = "Restricted",
                                authenticationMethod: String = NSURLAuthenticationMethodHTTPBasic) -> URLCredential {
        let credential = URLCredential.init(user: self.configuration.appId,
                                            password: oauthToken,
                                            persistence: .permanent)

        // saveToken = true
        // 키체인에 저장 시도
        if saveToken == true,
            self.saveToken(oauthToken) == false {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: 토큰 저장 실패.")
        }
        let protectionSpace = URLProtectionSpace.init(host: configuration.host,
                                                      port: port,
                                                      protocol: protocolType,
                                                      realm: realm,
                                                      authenticationMethod: authenticationMethod)
        URLCredentialStorage.shared.set(credential, for: protectionSpace)
        return credential
    }
    
    /// OAuth 토큰 리프레시 실행 메쏘드
    /// - Parameters:
    ///   - token: 리프레시할 토큰
    /// - Returns: Result 타입으로 토큰 스트링, 또는 에러 반환.
    private func refreshToken(_ token: String) async -> Result<String, Error> {
        return await withCheckedContinuation { continuation in
            oauth.renewAccessToken(withRefreshToken: token) { result in
                switch result {
                case .success(let success):
                    continuation.resume(returning: .success(success.credential.oauthToken))
                case .failure(let error):
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
    
    // MARK: Token with KeyChain
    
    /// 특정 클라우드 서비스의 토큰을 키체인에 저장하는 메쏘드
    /// - Parameter token: 저장할 토큰.
    func saveToken(_ token: String) -> Bool {
        let result = self.restoreToken()
        switch result {
            // 토큰 발견 시
        case .success(_):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 업데이트로 처리.")
            // 이미 토큰이 있는 경우, 업데이트
            return self.updateToken(token)
            
            // 토큰 미발견 시
        case .failure(_):
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 신규 저장.")
            let saveQuery: NSDictionary = [kSecClass: kSecClassGenericPassword,
                                       kSecAttrLabel: configuration.tokenLabel,
                            kSecAttrApplicationLabel: configuration.appId,
                         kSecValueData: token.data(using: .utf8, allowLossyConversion: false)!]
            
            let result = SecItemAdd(saveQuery, nil)
            guard result == errSecSuccess else {
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 저장 실패 = \(SecCopyErrorMessageString(result, nil)).")
                return false
            }
            // 토큰 저장 성공
            return true
        }
    }
    /// 특정 클라우드 서비스의 토큰을 키체인에서 찾아 업데이트하는 메쏘드
    /// - Parameter token: 저장할 토큰.
    func updateToken(_ token: String) -> Bool {
        let saveQuery: NSDictionary = [kSecClass: kSecClassGenericPassword,
                                   kSecAttrLabel: configuration.tokenLabel,
                        kSecAttrApplicationLabel: configuration.appId]
        let attributes: NSDictionary = [kSecValueData: token.data(using: .utf8, allowLossyConversion: false)!]

        let result = SecItemUpdate(saveQuery, attributes)
        guard result == errSecSuccess else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰 업데이트 실패 = \(SecCopyErrorMessageString(result, nil)).")
            return false
        }
        // 토큰 업데이트 성공
        return true
    }
    /// 특정 클라우드 서비스의 토큰을 키체인에서 복원하는 메쏘드
    /// - Returns: Result 타입으로 성공 시 토큰 반환. 실패 시 에러 반환.
    func restoreToken() -> Result<String, Error> {
        let searchQuery: NSDictionary = [kSecClass: kSecClassGenericPassword,
                                     kSecAttrLabel: configuration.tokenLabel,
                          kSecAttrApplicationLabel: configuration.appId,
                              kSecReturnAttributes: true,
                                    kSecReturnData: true]
        
        var searchedResult: CFTypeRef?
        let searchStatus = SecItemCopyMatching(searchQuery, &searchedResult)
        guard searchStatus == errSecSuccess,
              let checkedItem = searchedResult,
              let checkedData = checkedItem[kSecValueData] as? Data,
              let token = String.init(data: checkedData, encoding: .utf8) else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰을 찾을 수 없음.")
            // 실패
            return .failure(Files.Error.tokenFailed)
        }
        return .success(token)
    }

    /// 토큰을 키체인에서 제거하는 메쏘드
    /// - Returns: Result 타입으로 성공 시 true 반환. 실패 시 에러 반환.
    func removeToken() -> Result<Bool, Error> {
        let searchQuery: NSDictionary = [kSecClass: kSecClassKey,
                                     kSecAttrLabel: configuration.tokenLabel,
                          kSecAttrApplicationLabel: configuration.appId]
        
        let deleteStatus = SecItemDelete(searchQuery)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 토큰을 찾을 수 없음.")
            // 실패
            return .failure(Files.Error.tokenFailed)
        }
        return .success(true)
    }

}

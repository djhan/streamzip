//
//  CloudConfiguration.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 12/1/25.
//

import Foundation

// MARK: - Cloud Information Enumeration -
/// 클라우드 서버 정보
public enum CloudInformation {
    /// Host / 최상위 경로
    enum Host: String {
        /// OneDrive 의 Host / 최상위 경로
        case oneDrive = "onedrive.com"
    }

    /// API Host 주소
    enum APIHost: String {
        /// OneDrive API Host 주소
        case oneDrive = "graph.microsoft.com"
    }
    
    /// Token Label
    /// - 토큰 값을 가리키는 라벨명
    enum TokenLabel: String {
        /// OneDrive 의 Token Lable
        case oneDrive = "onedrive_Token_Label"
    }
}

// MARK: - Cloud Configuration Struct -
/// Cloud Configuration 구조체
/// - [참고 링크](https://github.com/alexiscn/CloudServiceKit) 에 따라 작성
public struct CloudConfiguration: Codable,
                                  Sendable {
    
    // MARK: - Codable Properties
    
    /// host
    let host: String
    /// token label
    let tokenLabel: String
    /// token string
    /// - 토큰 직접 저장 시 사용
    var token: String?
    /// API host
    let apiHost: String
    
    /// App ID
    let appId: String
    /// App Secret
    let appSecret: String
    /// Redirect URL 경로
    let redirectPath: String
    /// Redirect URL
    var redirectURL: URL {
        return URL.init(string: self.redirectPath)!
    }
    /// Authorize URL 경로
    let authorizePath: String
    /// Authorize URL
    var authorizeURL: URL {
        return URL.init(string: self.authorizePath)!
    }
    /// Access Token URL 경로
    let accessTokenPath: String?
    /// Access Token URL
    var accessTokenURL: URL? {
        guard let accessTokenPath else { return nil }
        return URL.init(string: accessTokenPath)
    }
    /// Response Type
    let responseType: String
    
    // MARK: OneDrive Propertis
    /// OneDrive 에만 필요
    /// - 현재는 `"User.Read", "Files.ReadWrite.All"`를 지정한다.
    var scopes: [String]?
    
    // MARK: Initialization
    init(host: String,
         tokenLabel: String,
         token: String? = nil,
         apiHost: String,
         appId: String,
         appSecret: String,
         redirectPath: String,
         authorizePath: String,
         accessTokenPath: String? = nil,
         responseType: String,
         scopes: [String]? = nil) {
        self.host = host
        self.tokenLabel = tokenLabel
        self.token = token
        self.apiHost = apiHost
        self.appId = appId
        self.appSecret = appSecret
        self.redirectPath = redirectPath
        self.authorizePath = authorizePath
        self.accessTokenPath = accessTokenPath
        self.responseType = responseType
        self.scopes = scopes
    }
}

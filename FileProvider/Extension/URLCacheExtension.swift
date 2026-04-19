//
//  URLCacheExtension.swift
//  EdgeView
//
//  Created by DJ.HAN on 4/18/26.
//  Copyright © 2026 DJ.HAN. All rights reserved.
//

import Foundation

import CommonLibrary

public extension URLCache {
    
    /// 특정 URL의 캐쉬 데이터 이동
    /// - Important: HTTP 가 아닌 일반 로컬 또는 FTP, SFTP 등의 캐쉬 데이터 이동 시 사용될 수 있다.
    /// - Parameters:
    ///   - originURL: 기존 캐쉬가 저장된 `URL`
    ///   - targetURL: 이동할 `URL`
    ///   - storagePolicy: 저장 정책. 기본값은 `allowed`
    /// - Returns: 성공 또는 실패 여부
    @discardableResult
    func moveNoneHTTPCache(from originURL: URL,
                           to targetURL: URL,
                           storagePolicy: URLCache.StoragePolicy = .allowed) -> Bool {
        let originURLRequest = URLRequest.createNoneHTTPRequest(originURL)
        let targetURLRequest = URLRequest.createNoneHTTPRequest(targetURL)
        return moveCache(from: originURLRequest, to: targetURLRequest, storagePolicy: storagePolicy)
    }
    
    /// 캐쉬 데이터 이동
    /// - Parameters:
    ///   - originURLRequest: 기존 캐쉬의 `URLRequest`
    ///   - targetURLRequest: 이동할 캐쉬의 `URLRequest`
    ///   - storagePolicy: 저장 정책. 기본값은 `allowed`
    /// - Returns: 성공 또는 실패 여부
    @discardableResult
    func moveCache(from originURLRequest: URLRequest,
                   to targetURLRequest: URLRequest,
                   storagePolicy: URLCache.StoragePolicy = .allowed) -> Bool {
        guard let cachedOriginResponse = self.cachedResponse(for: originURLRequest),
              let targetURL = targetURLRequest.url else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(originURLRequest.url?.absoluteString ?? "unknown") >> 캐쉬 정보가 없거나, 문제 발생")
            return false
        }
        let data = cachedOriginResponse.data
        self.removeCachedResponse(for: originURLRequest)
        let response = HTTPURLResponse(url: targetURL, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=2592000"])!
        let cachedTargetResponse = CachedURLResponse(response: response, data: data, userInfo: nil, storagePolicy: storagePolicy)
        self.storeCachedResponse(cachedTargetResponse, for: targetURLRequest)
        return true
    }
    
}

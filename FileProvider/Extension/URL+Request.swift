//
//  URL+Request.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 2/4/26.
//

import Foundation

extension URL {

    /// URLRequest용 URL 작성
    /// - 현재 URL 기준으로 작성한다.
    /// - Important: offset / length 를 추가해 사용할 때 "?offset=..."이란 식으로 사용하면 문제가 발생한다. 따라서 `URLComponent`를 이용해 작성하도록 한다.
    /// - Parameters:
    ///   - offset: Offset 값. 기본값은 0.
    ///   - length: Lengt 값. 기본값은 0.
    /// - Returns: `URL` 반환. 실패 시 널값 반환.
    public func requestURL(offset: Int64 = 0, length: Int64 = 0) -> URL? {
        // File의 Request를 생성
        if offset > 0,
           length > 0 {
            var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
            // file 스킴인 경우 URLCache의 디스크 캐싱을 위해 가상 호스트로 변환
            if components?.scheme == "file" {
                components?.scheme = "https"
                components?.host = "edgeview.local"
            }
            components?.queryItems = [
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "length", value: "\(length)")
            ]
            return components?.url
        }
        else {
            // offset / length가 지정되지 않은 경우
            return self.appendingPathComponent(path)
        }
    }

    /// URLRequest용 URL 작성
    /// - Important: offset / length 를 추가해 사용할 때 "?offset=..."이란 식으로 사용하면 문제가 발생한다. 따라서 `URLComponent`를 이용해 작성하도록 한다.
    /// - Parameters:
    ///   - path: 경로.
    ///   - offset: Offset 값. 기본값은 0.
    ///   - length: Lengt 값. 기본값은 0.
    /// - Returns: `URL` 반환. 실패 시 널값 반환.
    public func requestURL(at path: String, offset: Int64 = 0, length: Int64 = 0) -> URL? {
        // File의 Request를 생성
        if offset > 0,
           length > 0 {
            var components = URLComponents(url: self.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            // file 스킴인 경우 URLCache의 디스크 캐싱을 위해 가상 호스트로 변환
            if components?.scheme == "file" {
                components?.scheme = "https"
                components?.host = "edgeview.local"
            }
            components?.queryItems = [
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "length", value: "\(length)")
            ]
            return components?.url
        }
        else {
            // offset / length가 지정되지 않은 경우
            return self.appendingPathComponent(path)
        }
    }
}

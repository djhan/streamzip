//
//  URLRequestExtension.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation
import UniformTypeIdentifiers

import CommonLibrary

extension URLRequest {

    // MARK: - Create for none-HTTP Request
    /// HTTP 외의 URLRequest 작성
    /// - Important: FTP, SFTP, HTTP, 로컬 등의 `URLRequest` 작성 용도로 사용.
    /// - Parameter url: `URL`
    /// - Returns: `URLRequest`
    public static func createNoneHTTPRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    // MARK: - Set Value Methods
    
    mutating func setValue(authentication credential: URLCredential?, with type: AuthenticationType) {
        func base64(_ str: String) -> String {
            let plainData = str.data(using: .utf8)
            let base64String = plainData!.base64EncodedString(options: [])
            return base64String
        }
        
        guard let credential = credential else { return }
        switch type {
        case .basic:
            let user = credential.user?.replacingOccurrences(of: ":", with: "") ?? ""
            let pass = credential.password ?? ""
            let authStr = "\(user):\(pass)"
            if let base64Auth = authStr.data(using: .utf8)?.base64EncodedString() {
                self.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        case .digest:
            // handled by RemoteSessionDelegate
            break
        case .oAuth1:
            if let oauth = credential.password {
                self.setValue("OAuth \(oauth)", forHTTPHeaderField: "Authorization")
            }
        case .oAuth2:
            if let bearer = credential.password {
                self.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            }
        }
    }
    
    mutating func setValue(acceptCharset: String.Encoding, quality: Double? = nil) {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(acceptCharset.rawValue)
        if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
            if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
                self.setValue("\(charsetString);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Charset")
            } else {
                self.setValue(charsetString, forHTTPHeaderField: "Accept-Charset")
            }
        }
    }
    mutating func addValue(acceptCharset: String.Encoding, quality: Double? = nil) {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(acceptCharset.rawValue)
        if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
            if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
                self.addValue("\(charsetString);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Charset")
            } else {
                self.addValue(charsetString, forHTTPHeaderField: "Accept-Charset")
            }
        }
    }
    
    enum Encoding: String {
        case all = "*"
        case identity
        case gzip
        case deflate
    }
    
    mutating func setValue(acceptEncoding: Encoding, quality: Double? = nil) {
        if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
            self.setValue("\(acceptEncoding.rawValue);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Encoding")
        } else {
            self.setValue(acceptEncoding.rawValue, forHTTPHeaderField: "Accept-Encoding")
        }
    }
    
    mutating func addValue(acceptEncoding: Encoding, quality: Double? = nil) {
        if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
            self.addValue("\(acceptEncoding.rawValue);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Encoding")
        } else {
            self.addValue(acceptEncoding.rawValue, forHTTPHeaderField: "Accept-Encoding")
        }
    }
    
    mutating func setValue(acceptLanguage: Locale, quality: Double? = nil) {
        let langCode = acceptLanguage.identifier.replacingOccurrences(of: "_", with: "-")
        if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
            self.setValue("\(langCode);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Language")
        } else {
            self.setValue(langCode, forHTTPHeaderField: "Accept-Language")
        }
    }
    
    mutating func addValue(acceptLanguage: Locale, quality: Double? = nil) {
        let langCode = acceptLanguage.identifier.replacingOccurrences(of: "_", with: "-")
        if let qualityDesc = quality.flatMap({ String(format: "%.1f", min(0, max ($0, 1))) }) {
            self.addValue("\(langCode);q=\(qualityDesc)", forHTTPHeaderField: "Accept-Language")
        } else {
            self.addValue(langCode, forHTTPHeaderField: "Accept-Language")
        }
    }
    
    mutating func setValue(rangeWithOffset offset: Int64, length: Int) {
        if length > 0 {
            self.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        } else if offset > 0 && length < 0 {
            self.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
    }
    
    mutating func setValue(range: Range<Int>) {
        let range = max(0, range.lowerBound)..<range.upperBound
        if range.upperBound < Int.max && range.count > 0 {
            self.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        } else if range.lowerBound > 0 {
            self.setValue("bytes=\(range.lowerBound)-", forHTTPHeaderField: "Range")
        }
    }
    
    mutating func setValue(contentRange range: Range<Int64>, totalBytes: Int64) {
        let range = max(0, range.lowerBound)..<range.upperBound
        if range.upperBound < Int.max && range.count > 0 {
            self.setValue("bytes \(range.lowerBound)-\(range.upperBound - 1)/\(totalBytes)", forHTTPHeaderField: "Content-Range")
        } else if range.lowerBound > 0 {
            self.setValue("bytes \(range.lowerBound)-/\(totalBytes)", forHTTPHeaderField: "Content-Range")
        } else {
            self.setValue("bytes 0-/\(totalBytes)", forHTTPHeaderField: "Content-Range")
        }
    }
    
    mutating func setValue(mimeType: MimeType, charset: String.Encoding? = nil) {
        var parameter = ""
        if let charset = charset {
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(charset.rawValue)
            if let charsetString = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? {
                parameter = ";charset=" + charsetString
            }
        }
        
        self.setValue(mimeType.rawValue + parameter, forHTTPHeaderField: "Content-Type")
    }
    
    mutating func setValue(dropboxArgKey requestDictionary: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestDictionary, options: []) else {
            return
        }
        guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
        jsonString = jsonString.asciiEscaped().replacingOccurrences(of: "\\/", with: "/")
        
        self.setValue(jsonString, forHTTPHeaderField: "Dropbox-API-Arg")
    }
}


extension String {
    // MARK: - JSON
    /// JSON Dictionary로 초기화
    /// - Parameter jsonDictionary: `[String: Any]` 배열로 선언된 JSON 딕셔너리.
    init? (jsonDictionary: [String: Any]) {
        guard let data = Data(jsonDictionary: jsonDictionary) else {
            return nil
        }
        self.init(data: data, encoding: .utf8)
    }
    /// JSON 복원
    /// - `[String: Any]` 배열로 선언된 JSON 딕셔너리로 복원.
    /// - Parameter encoding: 인코딩 지정. 기본값은 UTF8.
    /// - Returns: `[String: Any]` 배열로 선언된 JSON 딕셔너리.
    func deserializeJSON(using encoding: String.Encoding = .utf8) -> [String: Any]? {
        guard let data = self.data(using: encoding) else {
            return nil
        }
        return data.deserializeJSON()
    }
    /// ASCII String 강제 변환
    /// - important: 아스키 코드에 대응하지 않는 문자는 u0041 과 같은 형태의 유니코드 문자값으로 변환된다.
    func asciiEscaped() -> String {
        var res = ""
        for char in self.unicodeScalars {
            let substring = String(char)
            if substring.canBeConverted(to: .ascii) {
                res.append(substring)
            } else {
                res = res.appendingFormat("\\u%04x", char.value)
            }
        }
        return res
    }
}

extension Data {
    // MARK: - JSON
    /// JSON Dictionary로 초기화
    /// - Parameter jsonDictionary: `[String: Any]` 배열로 선언된 JSON 딕셔너리.
    init? (jsonDictionary dictionary: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(dictionary) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return nil
        }
        self = data
    }
    /// JSON 복원
    /// - `[String: Any]` 배열로 선언된 JSON 딕셔너리로 복원.
    /// - Returns: `[String: Any]` 배열로 선언된 JSON 딕셔너리.
    func deserializeJSON() -> [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: self, options: [])) as? [String: Any]
    }
}

//
//  FileIProvidertem.swift
//  EdgeView
//
//  Created by DJ.HAN on 4/18/26.
//  Copyright © 2026 DJ.HAN. All rights reserved.
//

import Foundation

@preconcurrency import CommonLibrary
import EdgeFTPKit
internal import SMBClient

/// Path 트리밍 캐릭터 셋
public let pathTrimSet = CharacterSet(charactersIn: " /")


// MARK: - File Provider Item Protocol -
/// File Item Protocol
public protocol FileProviderItemConvertible: Sendable {
    
    // MARK: - Properties
    
    // MARK: Common
    
    /// 파일명
    var filename: String  { get }
    /// 경로
    var path: String  { get }
    /// 디렉토리 여부
    var isDirectory: Bool  { get }
    /// 생성일
    var creationDate: Date?  { get }
    /// 수정일
    var modificationDate: Date?  { get }
    /// 마지막 접근일
    var lastAccess: Date?  { get }
    /// 파일 크기
    /// - 폴더 또는 NULL로 주어질 경우 0으로 지정.
    var fileSize: Int64  { get }
    
    /// 감춤 파일 여부
    var isHidden: Bool  { get }
    
    /// 경로 변경 메쏘드
    /// - Important: URL, Archiverable은 경로 변경이 불가능하다. 시도 시, 실패 처리한다.
    @discardableResult
    mutating func updatePath(to path: String) -> Bool
}

extension FileProviderItemConvertible {
    /// 검색용 macPredicate 메쏘드
    /// - Returns: 스팟라잇용 키값에 매핑되는 딕셔너리 반환
    internal func mapPredicate() -> [String: Any] {
        var result = [String: Any]()
        result["title"] = self.filename
        result["filesize"] = self.fileSize
        result["isDirectory"] = self.isDirectory
        result["category"] = self.filename.category
        result["writer"] = self.filename.writer
        result["kMDItemDisplayName"] = self.filename
        result["kMDItemContentCreationDate"] = self.creationDate
        result["modificationDate"] = self.modificationDate
        result["kMDItemContentModificationDate"] = self.modificationDate
        
        return result
    }
}

// MARK: - FTP File Item Extension -
/// FTPItem 익스텐션
/// - 필요한 프로퍼티를 추가해서 사용한다.
extension FTPItem: @unchecked @retroactive Sendable,
                   FileProviderItemConvertible {

    // MARK: -Properties

    /// 생성일
    public var creationDate: Date? {
        return self.modificationDate
    }
    /// 마지막 접근일
    /// - 널값 반환
    public var lastAccess: Date? {
        return nil
    }
    
    /// 경로 변경 메쏘드
    /// - Parameter path: 바꾸려는 경로를 지정한다.
    /// - Returns: 성공 여부를 반환한다.
    @discardableResult
    public func updatePath(to path: String) -> Bool {
        guard self.path != path else {
            return false
        }
        self.path = path
        self.filename = path.lastPathComponent
        return true
    }
}


// MARK: - WebDAV File Item Struct -
/// WebDAV Item Struct
/// - 구조체로 선언 (클래스 오브젝트를 미포함)
public struct WebDAVItem: FileProviderItemConvertible {
    
    // MARK: - Static Method
    
    /// 리소스 키를 DAVResponse 의 속성으로 변환해 반환
    internal static func resourceKeyToDAVProp(_ key: URLResourceKey) -> String? {
        switch key {
        case URLResourceKey.fileSizeKey:
            return "getcontentlength"
        case URLResourceKey.creationDateKey:
            return "creationdate"
        case URLResourceKey.contentModificationDateKey:
            return "getlastmodified"
        case URLResourceKey.fileResourceTypeKey, URLResourceKey.mimeTypeKey:
            return "getcontenttype"
        case URLResourceKey.isHiddenKey:
            return "ishidden"
        case URLResourceKey.entryTagKey:
            return "getetag"
        case URLResourceKey.volumeTotalCapacityKey:
            // WebDAV doesn't have total capacity, but it's can be calculated via used capacity
            return "quota-used-bytes"
        case URLResourceKey.volumeAvailableCapacityKey:
            return "quota-available-bytes"
        default:
            return nil
        }
    }
    /// 특정 `URLResourceKey` 배열의 속성 값을 `Request` 용 텍스트로 반환
    internal static func propString(_ keys: [URLResourceKey]) -> String {
        var propKeys = ""
        for item in keys {
            if let prop = WebDAVItem.resourceKeyToDAVProp(item) {
                propKeys += "<D:prop><D:\(prop)/></D:prop>"
            }
        }
        if propKeys.isEmpty {
            propKeys = "<D:allprop/>"
        } else {
            propKeys += "<D:prop><D:resourcetype/></D:prop>"
        }
        return propKeys
    }
    /// 특정 `URLResourceKey` 배열의 속성 값을 `Request` 용 XML 데이터로 생성해 반환
    internal static func xmlProp(_ keys: [URLResourceKey]) -> Data {
        return "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n\(WebDAVItem.propString(keys))\n</D:propfind>".data(using: .utf8)!
    }
    
    // MARK: - Properties
    
    /// 파일명
    public var filename: String
    /// 경로
    public var path: String
    /// 디렉토리 여부
    public var isDirectory: Bool
    /// 생성일
    public var creationDate: Date?
    /// 수정일
    public var modificationDate: Date?
    /// 마지막 접근일
    public var lastAccess: Date?
    /// 파일 크기
    public var fileSize: Int64 = 0
    
    /// 감춤 파일 여부
    public var isHidden: Bool = false

    /// URL 경로
    internal var url: URL
    /// Mime 타입
    internal var mimeType: MimeType
    /// 태그
    internal var entryTag: String?

    // MARK: - Initialization
    /// 초기화
    /// - Parameter response: `WebDavResponse` 로 초기화.
    internal init(_ response: WebDavResponse) {
        self.url = response.url
        self.filename = response.prop["displayname"] ?? response.url.lastPathComponent
        let relativePath = self.url.relativePath
        self.path = relativePath.hasPrefix("/") ? relativePath : ("/" + relativePath)
        self.fileSize = Int64(response.prop["getcontentlength"] ?? "-1") ?? NSURLSessionTransferSizeUnknown
        self.creationDate = response.prop["creationdate"].flatMap { Date(rfcString: $0) }
        self.modificationDate = response.prop["getlastmodified"].flatMap { Date(rfcString: $0) }
        self.mimeType = response.prop["getcontenttype"].flatMap(MimeType.init(rawValue:)) ?? .Stream
        // response 에서 ishidden 이 누락된 경우, 정확한 감춤 여부 판단이 불가능하기 때문에 파일명 조건을 우선시한다.
        self.isHidden = self.filename.isHiddenFile ? true : (Int(response.prop["ishidden"] ?? "0") ?? 0) > 0
        self.isDirectory = (self.mimeType == .Directory) ? true : false
        self.entryTag = response.prop["getetag"]
    }

    /// 검색용 macPredicate 메쏘드 재선언
    /// - Returns: 스팟라잇용 키값에 매핑되는 딕셔너리 반환
    internal func mapPredicate() -> [String: Any] {
        var result = [String: Any]()
        result["title"] = self.filename
        result["filesize"] = self.fileSize
        result["isDirectory"] = self.isDirectory
        result["category"] = self.filename.category
        result["writer"] = self.filename.writer
        result["kMDItemDisplayName"] = self.filename
        result["kMDItemContentCreationDate"] = self.creationDate
        result["modificationDate"] = self.modificationDate
        result["kMDItemContentModificationDate"] = self.modificationDate
        // eTag 추가
        result["eTag"] = self.entryTag

        return result
    }
    
    /// 경로 변경 메쏘드
    /// - Parameter path: 바꾸려는 경로를 지정한다.
    /// - Returns: 성공 여부를 반환한다.
    @discardableResult
    public mutating func updatePath(to path: String) -> Bool {
        guard self.path != path else {
            return false
        }
        self.path = path
        self.filename = path.lastPathComponent
        return true
    }
}

// MARK: - MS OneDrive File Item Struct -

public struct OneDriveItem: FileProviderItemConvertible {
    // MARK: - Static Methods
    /// baseURL과 상대경로를 결합해 URL을 반환하는 static 메쏘드
    /// - Parameters:
    ///   - path: 상대 경로.
    ///   - modifier: 사용 용도를 지정하는 스트링으로 경로 뒤에 붙인다. e.g. `contents` 등.
    ///   - baseURL: baseURL 지정.
    ///   - route: `OneDriveFileProvider.Route`
    /// - Returns: `URL` 반환.
    static func url(of path: String, modifier: String?, baseURL: URL, route: OneDriveFilesProvider.Route) -> URL {
        var url: URL = baseURL
        let isId = path.hasPrefix("id:")
        var realPath: String = path.replacingOccurrences(of: "id:", with: "", options: .anchored)
        
        url.appendPathComponent(route.drivePath)
        
        if realPath.isEmpty {
            url.appendPathComponent("root")
        } else if isId {
            url.appendPathComponent("items")
        } else {
            url.appendPathComponent("root:")
        }
        
        realPath = realPath.trimmingCharacters(in: pathTrimSet)
        
        switch (modifier == nil, realPath.isEmpty, isId) {
        case (true, false, _):
            url.appendPathComponent(realPath)
        case (true, true, _):
            break
        case (false, true, _):
            url.appendPathComponent(modifier!)
        case (false, false, true):
            url.appendPathComponent(realPath)
            url.appendPathComponent(modifier!)
        case (false, false, false):
            url.appendPathComponent(realPath + ":")
            url.appendPathComponent(modifier!)
        }
        
        return url
    }
    
    /// URL 기반으로 상대적 경로 반환
    /// - Parameters:
    ///   - url: 상대적 경로 `URL`
    ///   - baseURL: baseURL 지정. 널값 지정 가능.
    ///   - route: `OneDriveFileProvider.Route`
    /// - Returns: 경로를 `String` 으로 반환.
    static func relativePath(of url: URL, baseURL: URL?, route: OneDriveFilesProvider.Route) -> String {
        let base = baseURL?.appendingPathComponent(route.drivePath).path ?? ""
        
        let crudePath = url.filePath.replacingOccurrences(of: base, with: "", options: .anchored)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if crudePath.hasPrefix("items/") {
            let components = crudePath.components(separatedBy: "/")
            return components.dropFirst().first.map { "id:\($0)" } ?? ""
        }
        else if crudePath.hasPrefix("root:") {
            return crudePath.components(separatedBy: ":").dropFirst().first ?? ""
        }
        // 그 외의 경우
        return ""
    }
    // MARK: - Properties
    
    /// 파일명
    public var filename: String
    /// 경로
    public var path: String
    /// 디렉토리 여부
    public var isDirectory: Bool
    /// 생성일
    public var creationDate: Date?
    /// 수정일
    public var modificationDate: Date?
    /// 마지막 접근일
    public var lastAccess: Date?
    /// 파일 크기
    public var fileSize: Int64 = 0
    
    /// 감춤 파일 여부
    public var isHidden: Bool = false

    /// URL 경로
    internal var url: URL
    /// Mime 타입
    internal var mimeType: MimeType
    /// 태그
    internal var entryTag: String?

    // MARK: OneDrive
    /// ID
    internal var id: String
    /// 해쉬값
    internal var fileHash: String?
    
    // MARK: - Initialization
    /// 초기화
    /// - Parameters:
    ///   - baseURL: baseURL 지정.
    ///   - route: `OneDriveFileProvider.Route` 지정.
    ///   - json: JSON 데이터 지정.
    ///   - showHiddenFile: 감춤 파일 표시 여부. false 로 지정한 경우, 파일명이 감춤 파일이면 널값을 반환한다. 기본값은 true.
    internal init?(baseURL: URL,
                   route: OneDriveFilesProvider.Route,
                   json: [String: Any],
                   showHiddenFile: Bool = true) {
        guard let name = json["name"] as? String else {
            return nil
        }
        // showHiddenFiles 이 false인 경우
        if showHiddenFile == false,
           name.isHiddenFile {
            return nil
        }
        
        guard let id = json["id"] as? String else {
            return nil
        }
        
        self.filename = name
        self.id = id
        
        if let refpath = (json["parentReference"] as? [String: Any])?["path"] as? String {
            let parentPath: String
            if let colonIndex = refpath.firstIndex(of: ":") {
                parentPath = String(refpath[refpath.index(after: colonIndex)...])
            } else {
                parentPath = refpath
            }
            self.path = parentPath.appendingPathComponent(name)
        } else {
            self.path = "id:\(id)"
        }
        
        self.url = Self.url(of: path, modifier: nil, baseURL: baseURL, route: route)
        
        // 파일명이 . 으로 시작하는 경우 hidden file로 간주
        if filename.hasPrefix(".") {
            self.isHidden = true
        }
        self.fileSize = (json["size"] as? NSNumber)?.int64Value ?? -1
        self.creationDate = (json["createdDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.modificationDate = (json["lastModifiedDateTime"] as? String).flatMap { Date(rfcString: $0) }
        self.isDirectory = json["folder"] != nil ? true : false
        self.mimeType = ((json["file"] as? [String: Any])?["mimeType"] as? String).flatMap(MimeType.init(rawValue: )) ?? .Stream
        self.entryTag = json["eTag"] as? String
        self.isHidden = self.filename.isHiddenFile
        let hashes = (json["file"] as? [String: Any])?["hashes"] as? [String: Any]
        // checks for both sha1 or quickXor. First is available in personal drives, second in business one.
        self.fileHash = (hashes?["sha1Hash"] as? String) ?? (hashes?["quickXorHash"] as? String)
    }
    
    /// 경로 변경 메쏘드
    /// - Parameter path: 바꾸려는 경로를 지정한다.
    /// - Returns: 성공 여부를 반환한다.
    @discardableResult
    public mutating func updatePath(to path: String) -> Bool {
        guard self.path != path else {
            return false
        }
        self.path = path
        self.filename = path.lastPathComponent
        return true
    }
}

// MARK: - SMB File Item Struct -
public struct SMBItem: FileProviderItemConvertible {
    
    // MARK: - Properties
    
    /// 파일명
    public var filename: String
    /// 경로
    public var path: String
    /// 디렉토리 여부
    public var isDirectory: Bool
    /// 생성일
    public var creationDate: Date?
    /// 수정일
    public var modificationDate: Date?
    /// 마지막 접근일
    public var lastAccess: Date?
    /// 파일 크기
    public var fileSize: Int64 = 0
    
    /// 감춤 파일 여부
    public var isHidden: Bool = false

    // MARK: SMB Properties
    /// 읽기만 가능 여부
    public var isReadOnly: Bool
    /// 시스템 파일 여부
    public var isSystem: Bool
    /// 압축 파일 여부
    var isArchive: Bool
    
    // MARK: - Initialization
    /// `File` 로 초기화
    /// - Parameters:
    ///   - file: SMBClient 패키지에서 선언된 `File`.
    ///   - path: File이 속한 경로.
    init(_ file: File, at path: String) {
        self.filename = file.name
        self.path = path.appendingPathComponent(file.name)
        self.isDirectory = file.isDirectory
        self.creationDate = file.creationTime
        self.modificationDate = file.creationTime
        self.lastAccess = file.lastAccessTime
        self.fileSize = Int64(file.size)
        self.isHidden = file.name.hasPrefix(".") == true ? true : file.isHidden
        self.isReadOnly = file.isReadOnly
        self.isSystem = file.isSystem
        self.isArchive = file.isArchive
    }
    /// 루트 경로 초기화
    /// - 개별 패러미터로 초기화
    /// - Parameters:
    ///   - path: 루트 경로.
    ///   - filename: 파일명.
    ///   - creationDate: 생성일을 UInt64로 지정한다.
    ///   - lastAccess: 마지막 접근일을 UInt64로 지정한다.
    ///   - fileSize: 파일 크기.
    ///   - isDirectory: 디렉토리 여부.
    ///   - isHidden: 감춤 파일 여부.
    ///   - isReadOnly: 읽기 전용 파일 여부.
    ///   - isSystem: 시스템 파일 여부.
    ///   - isArchive: 압축 파일 여부.
    init(path: String,
         filename: String,
         creationDate: UInt64?,
         lastAccess: UInt64?,
         fileSize: Int64,
         isDirectory: Bool,
         isHidden: Bool,
         isReadOnly: Bool,
         isSystem: Bool,
         isArchive: Bool) {
        
        /// UInt64 값을 날짜로 바꾸는 내부 메쏘드
        func date(_ raw: UInt64) -> Date {
            let timeInterval = Double(raw) / 10_000_000
            return Date(timeIntervalSince1970: timeInterval - 11644473600)
        }
        let creationDate = creationDate != nil ? date(creationDate!) : nil
        self.path = path
        self.filename = filename
        self.creationDate = creationDate
        self.modificationDate = creationDate
        self.lastAccess = lastAccess != nil ? date(lastAccess!) : nil
        self.fileSize = fileSize
        self.isDirectory = isDirectory
        self.isHidden = filename.hasPrefix(".") == true ? true : isHidden
        self.isReadOnly = isReadOnly
        self.isSystem = isSystem
        self.isArchive = isArchive
    }
    
    /// 경로 변경 메쏘드
    /// - Parameter path: 바꾸려는 경로를 지정한다.
    /// - Returns: 성공 여부를 반환한다.
    @discardableResult
    public mutating func updatePath(to path: String) -> Bool {
        guard self.path != path else {
            return false
        }
        self.path = path
        self.filename = path.lastPathComponent
        return true
    }
}

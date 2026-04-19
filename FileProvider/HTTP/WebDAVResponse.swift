//
//  WebDAVResponse.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

import CommonLibrary

// MARK: - WebDAV Response Struct-
struct WebDavResponse {
    
    // MARK: - Properties
    /// URL
    let url: URL
    /// URL 경로 `String`
    let urlString: String
    /// 상태
    let status: Int?
    /// 속성값
    let prop: [String: String]
    
    /// 퍼센트 값을 공백으로 변환할 때 사용하는 상수
    static let urlAllowed = CharacterSet(charactersIn: " ").inverted
    
    // MARK: - Initialization
    init?(_ node: AEXMLElement,
          baseURL: URL?) {
        
        /// 일반 경로 반환
        func standardizePath(_ str: String) -> String {
            let trimmedStr = str.hasPrefix("/") ? String(str[str.index(after: str.startIndex)...]) : str
            return trimmedStr.addingPercentEncoding(withAllowedCharacters: .filePathAllowed) ?? str
        }
        
        // find node names with namespace
        var hreftag = "href"
        var statustag = "status"
        var propstattag = "propstat"
        for node in node.children {
            if node.name.lowercased().hasSuffix("href") {
                hreftag = node.name
            }
            if node.name.lowercased().hasSuffix("status") {
                statustag = node.name
            }
            if node.name.lowercased().hasSuffix("propstat") {
                propstattag = node.name
            }
        }
        
        guard let hrefString = node[hreftag].value else {
            return nil
        }
        
        // Percent-encoding space, some servers return invalid urls which space is not encoded to %20
        let hrefStrPercented = hrefString.addingPercentEncoding(withAllowedCharacters: Self.urlAllowed) ?? hrefString
        // trying to figure out relative path out of href
        let hrefAbsolute = URL(string: hrefStrPercented, relativeTo: baseURL)?.absoluteURL
        let relativePath: String
        if hrefAbsolute?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) == baseURL?.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) {
            relativePath = hrefAbsolute?.path.replacingOccurrences(of: baseURL?.absoluteURL.filePath ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        } else {
            relativePath = hrefAbsolute?.absoluteString.replacingOccurrences(of: baseURL?.absoluteString ?? "", with: "", options: .anchored, range: nil) ?? hrefString
        }
        let hrefURL = URL(string: standardizePath(relativePath), relativeTo: baseURL) ?? baseURL
        
        guard let url = hrefURL?.standardized else {
            return nil
        }
        
        // reading status and properties
        var status: Int?
        let statusDesc = (node[statustag].string).components(separatedBy: " ")
        if statusDesc.count > 2 {
            status = Int(statusDesc[1])
        }
        var propDic = [String: String]()
        let propStatNode = node[propstattag]
        for node in propStatNode.children where node.name.lowercased().hasSuffix("status"){
            statustag = node.name
            break
        }
        let statusDesc2 = (propStatNode[statustag].string).components(separatedBy: " ")
        if statusDesc2.count > 2 {
            status = Int(statusDesc2[1])
        }
        var proptag = "prop"
        for tnode in propStatNode.children where tnode.name.lowercased().hasSuffix("prop") {
            proptag = tnode.name
            break
        }
        for propItemNode in propStatNode[proptag].children {
            let key = propItemNode.name.components(separatedBy: ":").last!.lowercased()
            guard propDic.index(forKey: key) == nil else { continue }
            propDic[key] = propItemNode.value
            if key == "resourcetype" && propItemNode.xml.contains("collection") {
                propDic["getcontenttype"] = MimeType.Directory.rawValue
            }
        }
        self.url = url
        self.urlString = hrefString
        self.status = status
        self.prop = propDic
    }
    
    /// XML 데이터 기반으로 파싱 실행, 아이템 목록을 반환하는 Static 메쏘드
    /// - Parameters:
    ///   - xmlResponse: `Data` 타입의 XML.
    ///   - baseURL: Base URL.
    /// - Returns: `WebDavResponse` 배열 반환.
    static func parse(xmlResponse: Data, baseURL: URL?) -> [WebDavResponse] {
        guard let xml = try? AEXMLDocument(xml: xmlResponse) else {
            return []
        }
        var result = [WebDavResponse]()
        var rootnode = xml.root
        var responsetag = "response"
        for node in rootnode.all ?? [] where node.name.lowercased().hasSuffix("multistatus") {
            rootnode = node
        }
        for node in rootnode.children where node.name.lowercased().hasSuffix("response") {
            responsetag = node.name
            break
        }
        for responseNode in rootnode[responsetag].all ?? [] {
            if let webDavResponse = WebDavResponse(responseNode, baseURL: baseURL) {
                result.append(webDavResponse)
            }
        }
        return result
    }
}

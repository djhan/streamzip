//
//  Constants.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 10/24/25.
//

import Foundation

// MARK: - Typealiases -

/// 진행율 핸들러 typealias
/// - Parameters:
///   - totalUnitCount: 전체 갯수. 하위 실행 갯수를 포함하지 않는다.
///   - completedUnitCount: 진행 갯수. 하위 진행 갯수를 포함하지 않는다.
///   - fractionCompleted: 진행율. 하위 진행 갯수를 포함한 진행율을 반환한다.
///   - work: 진행 중 작업 명을 표시하기 위한 `ProgressWork.Label`. 옵셔널.
///   - label: 진행 아이템 명. 옵셔널.
public typealias ProgressHandler = @Sendable (_ totalUnitCount: Int64,
                                              _ completedUnitCount: Int64,
                                              _ fractionCompleted: Double,
                                              _ work: ProgressWork.Label?,
                                              _ label: String?) -> Void
// MARK: - Progress Work Enumeration -
/// Progress 종류
public enum ProgressWork: String {
    /// 파일 열기 작업
    /// - 전반적인 이미지/파일 열기 작업의 통칭
    case loading        = "Loading Files"
    
    /// 아카이브 파싱 작업
    case parseArchive   = "Parse Archive"
    /// 아카이브 압축 해제 작업
    case extractArchive = "Extract Archive"
    /// 파일 압축 작업
    case compressFile   = "Compress Files"
    
    /// 드라이브 마운트 작업
    case mountDrive     = "Mount Drive"
    
    /// 파일 목록 생성
    case list           = "List Files"
    /// 파일 정보 확인
    case information    = "Get Information of File"
    /// 검색 작업
    case search         = "Search Files"
    /// 파일 정렬 작업
    case sort           = "Sort Files"
    /// 파일 쓰기/업로드
    case write          = "Write File"
    /// 파일 다운로드
    case download       = "Download File"
    /// 파일 저장 작업
    case save           = "Save Files"

    /// 파일 추가 작업
    case add            = "Add Files"
    /// 파일 제거 작업
    case remove         = "Remove Files"
    /// 파일 이동 작업
    case move           = "Move Files"
    /// 파일 복사 작업
    case copy           = "Copy Files"
    /// 파일 변경 작업
    case change         = "Change Files"
    
    /// 이미지 생성을 비롯한 각종 작업
    case processImage   = "Process Image"
    /// 레이아웃 준비 작업
    /// - 이어보기 뷰에서 사용
    case prepareLayout  = "Prepare Layout"
    
    /// 실제 작업명 및 상태를 표시하기 위한 라벨
    public enum Label: Sendable {
        /// 파일 열기 작업
        case loading
        /// 파일 열기 작업
        /// - 전체 및 진행상태 표시.
        case loadingProgress(_ total: UInt64, _ progressed: UInt64)

        /// 아카이브 파싱 작업
        case parseArchive
        /// 아카이브 파싱 작업
        /// - 전체 및 진행상태 표시.
        case parseArchiveProgress(_ total: UInt64, _ progressed: UInt64)
        /// 아카이브 압축 해제 작업
        case extractArchive
        /// 아카이브 압축 해제 작업
        /// - 전체 및 진행상태 표시.
        case extractArchiveProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 압축 작업
        case compressFile
        /// 아카이브 압축 해제 작업
        /// - 전체 및 진행상태 표시.
        case compressFileProgress(_ total: UInt64, _ progressed: UInt64)

        /// 드라이브 마운트 작업
        case mountDrive
        
        /// 파일 목록 생성
        case list
        /// 파일 목록 생성
        /// - 전체 및 진행상태 표시.
        case listProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 정보 확인
        case information
        /// 검색 작업
        case search
        /// 파일 정렬 작업
        case sort
        /// 파일 쓰기/업로드
        case write
        /// 파일 쓰기/업로드
        /// - 전체 및 진행상태 표시.
        case writeProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 다운로드
        case download
        /// 파일 다운로드
        /// - 전체 및 진행상태 표시.
        case downloadProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 읽기 (로컬)
        case read
        /// 파일 읽기 (로컬)
        /// - 전체 및 진행상태 표시.
        case readProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 저장 작업
        case save
        /// 파일 저장 작업
        /// - 전체 및 진행상태 표시.
        case saveProgress(_ total: UInt64, _ progressed: UInt64)

        /// 파일 추가 작업 (주로 단일 파일)
        case add
        /// 파일 추가 작업
        /// - 전체 및 진행상태 표시.
        case addProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 제거 작업
        case remove
        /// 파일 제거 작업 (주로 단일 파일)
        /// - 전체 및 진행상태 표시.
        case removeProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 이동 작업 (주로 단일 파일)
        case move
        /// 파일 이동 작업
        /// - 전체 및 진행상태 표시.
        case moveProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 복사 작업 (주로 단일 파일)
        case copy
        /// 파일 복사 작업
        /// - 전체 및 진행상태 표시.
        case copyProgress(_ total: UInt64, _ progressed: UInt64)
        /// 파일 변경 작업 (주로 단일 파일)
        case change
        /// 파일 변경 작업
        /// - 전체 및 진행상태 표시.
        case changeProgress(_ total: UInt64, _ progressed: UInt64)

        /// 이미지 생성을 비롯한 각종 작업
        case processImage
        /// 레이아웃 준비 작업
        case prepareLayout

        /// 에러 발생
        case error(_ error: Error)
        /// 작업 취소
        case cancel
    }
}
/// JSON 타입
public typealias JSONDictionary = [String: Any]

/// 진행상태 연속성
internal typealias ProgressContinuation = AsyncStream<TotalBytesAndProgressed>.Continuation
/// 완료 확인 연속성
internal typealias ResultContinuation<T> = CheckedContinuation<T, Error>
/// 연속성 튜플
/// - Parameters:
///   - progress: `ProgressContinuation`
///   - result: `ResultContinuation`
internal typealias Continuations<T> = (progress: ProgressContinuation, result: ResultContinuation<T>)

/// 진행상태 튜플
/// - Parameters:
///   - totalBytes: 전체 크기.
///   - progressed: 진행된 크기.
internal typealias TotalBytesAndProgressed = (totalBytes: Int64, progressed: Int64)


// MARK: - Errors -

// MARK: - HTTP Error
/// HTTP Error Protocol
public protocol HTTPError: LocalizedError,
                            CustomStringConvertible {
    /// HTTP status code returned for error by server.
    var code: HTTPErrorCode { get }
    /// Path of file/folder casued that error
    var path: String { get }
    /// Contents returned by server as error description
    var serverDescription: String? { get }
}

extension HTTPError {
    public var description: String {
        return "Status %@: %@".localized(with: [code.rawValue, code.description])
        //return String(localized: "Status \(code.rawValue): \(code.description)")
    }
}

/// HTTP status codes as an enum.
public enum HTTPErrorCode: Int,
                           CustomStringConvertible,
                           Sendable {
    /// `Continue` informational status with HTTP code 100
    case `continue` = 100
    /// `Switching Protocols` informational status with HTTP code 101
    case switchingProtocols = 101
    /// `Processing` informational status with HTTP code 102
    case processing = 102
    /// `OK` success status with HTTP code 200
    case ok = 200
    /// `Created` success status with HTTP code 201
    case created = 201
    /// `Accepted` success status with HTTP code 202
    case accepted = 202
    /// `Non Authoritative Information` success status with HTTP code 203
    case nonAuthoritativeInformation = 203
    /// `No Content` success status with HTTP code 204
    case noContent = 204
    /// `ResetcContent` success status with HTTP code 205
    case resetContent = 205
    /// `Partial Content` success status with HTTP code 206
    case partialContent = 206
    /// `Multi Status` success status with HTTP code 207
    case multiStatus = 207
    /// `Already Reported` success status with HTTP code 208
    case alreadyReported = 208
    /// `IM Used` success status with HTTP code 226
    case imUsed = 226
    /// `Multiple Choices` redirection status with HTTP code 300
    case multipleChoices = 300
    /// `Moved Permanently` redirection status with HTTP code 301
    case movedPermanently = 301
    /// `Found` redirection status with HTTP code 302
    case found = 302
    /// `See Other` redirection status with HTTP code 303
    case seeOther = 303
    /// `Not Modified` redirection status with HTTP code 304
    case notModified = 304
    /// `Use Proxy` redirection status with HTTP code 305
    case useProxy = 305
    /// `Switch Proxy` redirection status with HTTP code 306
    case switchProxy = 306
    /// `Temporary Redirect` redirection status with HTTP code 307
    case temporaryRedirect = 307
    /// `Permanent Redirect` redirection status with HTTP code 308
    case permanentRedirect = 308
    /// `Bad Request` client error status with HTTP code 400
    case badRequest = 400
    /// `Unauthorized` client error status with HTTP code 401
    case unauthorized = 401
    /// `Payment Required` client error status with HTTP code 402
    case paymentRequired = 402
    /// `Forbidden` client error status with HTTP code 403
    case forbidden = 403
    /// `Not Found` client error status with HTTP code 404
    case notFound = 404
    /// `Method Not Allowed` client error status with HTTP code 405
    case methodNotAllowed = 405
    /// `Not Acceptable` client error status with HTTP code 406
    case notAcceptable = 406
    /// `Proxy Authentication Required` client error status with HTTP code 407
    case proxyAuthenticationRequired = 407
    /// `Request Timeout` client error status with HTTP code 408
    case requestTimeout = 408
    /// `Conflict` client error status with HTTP code 409
    case conflict = 409
    /// `Gone` client error status with HTTP code 410
    case gone = 410
    /// `Length Required` client error status with HTTP code 411
    case lengthRequired = 411
    /// `Precondition Failed` client error status with HTTP code 412
    case preconditionFailed = 412
    /// `Payload Too Large` client error status with HTTP code 413
    case payloadTooLarge = 413
    /// `URI Too Long` client error status with HTTP code 414
    case uriTooLong = 414
    /// `Unsupported Media Type` status with HTTP code 415
    case unsupportedMediaType = 415
    /// `Range Not Satisfiable` client error status with HTTP code 416
    case rangeNotSatisfiable = 416
    /// `Expectation Failed` client error status with HTTP code 417
    case expectationFailed = 417
    /// `Misdirected Request` client error status with HTTP code 421
    case misdirectedRequest = 421
    /// `Unprocessable Entity` client error status with HTTP code 422
    case unprocessableEntity = 422
    /// `Locked` client error status with HTTP code 423
    case locked = 423
    /// `Failed Dependency` client error status with HTTP code 424
    case failedDependency = 424
    /// `Unordered Collection` client error status with HTTP code 425
    case unorderedCollection = 425
    /// `Upgrade Required` client error status with HTTP code 426
    case upgradeRequired = 426
    /// `Precondition Required` client error status with HTTP code 428
    case preconditionRequired = 428
    /// `Too Many Requests` client error status with HTTP code 429
    case tooManyRequests = 429
    /// `Request Header Fields Too Large` client error status with HTTP code 431
    case requestHeaderFieldsTooLarge = 431
    /// `Unavailable For Legal Reasons` client error status with HTTP code 451
    case unavailableForLegalReasons = 451
    /// `Internal Server Error` server error status with HTTP code 500
    case internalServerError = 500
    /// `Bad Gateway` server error status with HTTP code 502
    case badGateway = 502
    /// `Service Unavailable` server error status with HTTP code 503
    case serviceUnavailable = 503
    /// `Gateway Timeout` server error status with HTTP code 504
    case gatewayTimeout = 504
    /// `HTTP Version Not Supported` server error status with HTTP code 505
    case httpVersionNotSupported = 505
    /// `Variant Also Negotiates` server error status with HTTP code 506
    case variantAlsoNegotiates = 506
    /// `Insufficient Storage` server error status with HTTP code 507
    case insufficientStorage = 507
    /// `Loop Detected` server error status with HTTP code 508
    case loopDetected = 508
    /// `Bandwidth Limit Exceeded` server error status with HTTP code 509
    case bandwidthLimitExceeded = 509
    /// `Not Extended` server error status with HTTP code 510
    case notExtended = 510
    /// `Network Authentication Required` server error status with HTTP code 511
    case networkAuthenticationRequired = 511
    
    /// 알 수 없는 에러 = 0
    case unknownError = 0
    
    fileprivate static let status0: [Int: String] = [0: "Unknown Error"]
    fileprivate static let status1xx: [Int: String] = [100: "Continue", 101: "Switching Protocols", 102: "Processing"]
    fileprivate static let status2xx: [Int: String] = [200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used"]
    fileprivate static let status3xx: [Int: String] = [300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 306: "Switch Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect"]
    fileprivate static let status4xx: [Int: String] = [400: "Bad Request", 401: "Unauthorized/Expired Session", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Payload Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 421: "Misdirected Request", 422: "Unprocessable Entity", 423: "Locked", 424: "Failed Dependency", 425: "Unordered Collection", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons"]
    fileprivate static let status5xx: [Int: String] = [500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 509: "Bandwidth Limit Exceeded", 510: "Not Extended", 511: "Network Authentication Required"]
    
    public var description: String {
        switch self.rawValue {
        case 0: return HTTPErrorCode.status0[self.rawValue]!
        case 100...102: return HTTPErrorCode.status1xx[self.rawValue]!
        case 200...208, 226: return HTTPErrorCode.status2xx[self.rawValue]!
        case 300...308: return HTTPErrorCode.status3xx[self.rawValue]!
        case 400...417, 421...426: fallthrough
        case 428, 429, 431, 451: return HTTPErrorCode.status4xx[self.rawValue]!
        case 500...511: return HTTPErrorCode.status5xx[self.rawValue]!
        default: return typeDescription
        }
    }
    
    public var localizedDescription: String {
        return HTTPURLResponse.localizedString(forStatusCode: self.rawValue)
    }
    
    /// Description of status based on first digit which indicated fail or success.
    public var typeDescription: String {
        switch self.rawValue {
        case 100...199: return "Informational"
        case 200...299: return "Success"
        case 300...399: return "Redirection"
        case 400...499: return "Client Error"
        case 500...599: return "Server Error"
        default: return "Unknown Error"
        }
    }
}

// MARK: - XML Error
/// A type representing error value that can be thrown or inside `error` property of `AEXMLElement`.
public enum AEXMLError: Error {
    /// This will be inside `error` property of `AEXMLElement` when subscript is used for not-existing element.
    case elementNotFound
    
    /// This will be inside `error` property of `AEXMLDocument` when there is no root element.
    case rootElementMissing
    
    /// `AEXMLDocument` can throw this error on `init` or `loadXMLData` if parsing with `XMLParser` was not successful.
    case parsingFailed
}

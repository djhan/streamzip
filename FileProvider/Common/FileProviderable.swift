//
//  FileProviderable.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 10/27/25.
//

import Foundation
import CommonLibrary

// MARK: - File Provider Protocol -
/// FileProviderable 프로토콜
/// - FileProvider가 사용하는 프로토콜.
public protocol FileProviderable: Actor {
    
    // MARK: - Generic
    /// FileProviderItemConvertible 타입의 아이템을 지정해 사용
    associatedtype FileItem: FileProviderItemConvertible
    
    // MARK: - Properties
    
    /// 기본 Base URL
    var baseURL: URL? { get }

    /// URLCache
    var urlCache: URLCache? { get set }

    /// 최대 동시 업로드 개수
    /// - 기본값은 1 (순차 업로드). HTTP 기반 프로바이더는 5, SFTP는 3 등으로 설정 가능.
    var maxConcurrentUploads: Int { get }

    // MARK: - Methods
    
    /// FileItem 생성
    /// - 단독 FileItem을 생성하며, 주로 Root FileItem 생성에 사용한다.
    /// - Parameter path: 생성 경로.
    /// - Returns: 해당 경로의 `FileItem` 초기화 후 반환. 실패 시 에러를 던진다.
    func makeItem(of path: String) async throws -> FileItem

    /// 특정 path 내부의 아이템을 목록으로 가져오는 메쏘드
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - showHiddenFiles: 숨김 파일 표시 여부.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    func contents(of path: String,
                  showHiddenFiles: Bool) async -> Result<[FileItem], Error>
    
    /// 특정 경로 파일의 크기를 구한다
    /// - Parameter path: 파일 경로를 지정한다.
    /// - Returns: Result 타입으로 UInt64 형의 길이를 반환한다.
    func fileSize(of path: String) async -> Result<UInt64, Error>
        
    /// 특정 경로가 디렉토리인지 여부를 반환하는 비동기 메쏘드
    func isDirectory(of path: String) async -> Bool

    /// 특정 경로의 전체 Data를 비동기로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 Data 또는 에러 반환
    func data(of path: String,
              _ progressHandler: @escaping ProgressHandler) async -> Result<Data, Error>
    /// 특정 경로의 특정 영역의 Data를 비동기로 반환
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - offset: 다운로드 개시 지점. 0인 경우 시작부터 다운로드.
    ///    - length: 다운로드 받을 데이터 길이. 0인 경우 전체 다운로드 실행.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 Data 또는 에러 반환
    func data(of path: String,
              offset: Int64,
              length: Int64,
              _ progressHandler: @escaping ProgressHandler) async -> Result<Data, Error>
    /// 특정 경로의 파일을 비동기로 로컬 URL에 다운로드
    /// - Parameters:
    ///    - path: 파일 경로를 지정한다.
    ///    - localFolder: 다운받을 로컬 폴더를 지정한다. 파일명은 그대로 유지한다.
    ///    - conflictHandler: 다운받을 위치에 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러.
    /// - Returns: Result 타입으로 다운받은 파일 URL 또는 에러 반환
    func download(from path: String,
                  toLocalFolder localFolder: URL,
                  conflictHandler: (@Sendable () async -> Files.Conflict)?,
                  _ progressHandler: @escaping ProgressHandler) async -> Result<URL, Error>

    /// 특정 `FileItem` 제거
    /// - Parameters:
    ///    - item: 제거할 `FileItem`
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func remove(_ item: FileItem) async -> Result<Bool, Error>
    /// 특정 경로의 파일 제거
    /// - Parameters:
    ///    - path: 제거할 파일 경로.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func remove(of path: String) async -> Result<Bool, Error>

    /// 파일 이동
    /// - Parameters:
    ///   - originPath: 원래 파일 경로.
    ///   - targetPath: 새로운 파일 경로.
    ///   - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///   - progressHandler: 전체 갯수, 진행 갯수, 다운로드 파일명을 반환하는 완료 핸들러. 널값 지정 가능.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func move(from originPath: String,
              to targetPath: String,
              conflictHandler: (@Sendable () async -> Files.Conflict)?,
              _ progressHandler: ProgressHandler?) async -> Result<Bool, Error>
    /// 파일명 변경
    /// - Parameters:
    ///    - parentPath: 해당 파일이 속한 경로.
    ///    - oldFilename: 원래 파일명.
    ///    - newFilename: 새로운 파일명.
    /// - Returns: Result 타입으로 성공 여부 또는 에러 반환.
    func rename(in parentPath: String,
                from oldFilename: String,
                to newFilename: String) async -> Result<Bool, Error>
    
    /// 파일 업로드
    /// - Important: 폴더인 경우, 서버에 디렉토리를 생성하기만 한다. 폴더 내용까지 올리려면 `writeFolder` 메쏘드를 사용한다.
    /// - Parameters:
    ///    - originPath: 업로드할 로컬 파일 경로.
    ///    - targetPath: 파일이 올라갈 FTP 경로, 업로드할 파일/폴더명까지 포함해야 한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func write(from originPath: String,
               to targetPath: String,
               conflictHandler: (@Sendable () async -> Files.Conflict)?,
               _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, Error>
    /// 데이터 업로드
    /// - Parameters:
    ///    - data: 업로드할 Data
    ///    - targetPath: 파일이 올라갈 FTP 경로
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func write(from data: Data,
               to targetPath: String,
               conflictHandler: (@Sendable () async -> Files.Conflict)?,
               _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, Error>
    
    /// 특정 경로 파일의 충돌 확인
    /// - 파일 충돌이 발생하는 경우, 사용자에게 덮어쓰기/병합/건너뛰기 여부를 확인한다.
    /// - Parameters:
    ///   - path: 파일 충돌 여부 확인 경로.
    ///   - conflictHandler: 덮어쓰기/병합/거너뛰기 확인용 완료 핸들러.
    /// - Returns: Result 타입으로 충돌 파일이 없거나 기존 파일을 삭제하는 데 성공하면 true를 반환한다.
    /// 기존 파일이 있지만 병합/건너뛰기 발생 시에는 false를 반환한다.
    /// 충돌이 있는데도 사용자 확인을 받지 못한 경우, 또는 삭제 중 문제가 발생하면 에러를 반환한다.
    func resolveFileConflict(of path: String, _ conflictHandler: (@Sendable () async -> Files.Conflict)?) async -> Result<Bool, Error>
}

// MARK: - Progress Extension -
extension Progress {
    /// 현재 업로드/다운로드 중인 아이템 이름을 저장하기 위한 userInfo 키
    public static let currentItemKey = ProgressUserInfoKey("currentItem")
}

// MARK: - NSPredicate Extension -
/// NSPredicate를 Sendable로 확장
/// - NSPredicate는 내부적으로 thread-safe하게 설계되어 있으므로 unchecked Sendable로 확장한다
extension NSPredicate: @unchecked @retroactive Sendable { }

// MARK: - FileProviderable Extension -
extension FileProviderable {
    
    /// 최대 동시 업로드 개수 기본값
    /// - 기본값은 1 (순차 업로드). 각 프로바이더에서 override 가능.
    public var maxConcurrentUploads: Int { 1 }
    
    // MARK: - List Methods
    
    /// 재귀적 목록 생성 비동기 메쏘드
    /// - Parameters:
    ///   - path: 목록 생성 경로
    ///   - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    ///   - foundItemsHandler: 중간값 반환 핸들러
    ///   - progressHandler: 전체 갯수, 진행 갯수, 진행율 반환. 진행 아이템 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    public func contentsRecursively(path: String,
                                    showHiddenFiles: Bool = false,
                                    foundItemsHandler: (@Sendable (_ contents: [FileItem]) -> Void)? = nil,
                                    _ progressHandler: @escaping ProgressHandler) async -> Result<[FileItem], Error> {
        return await self.contentsRecursively(path: path,
                                              showHiddenFiles: showHiddenFiles,
                                              foundItemsHandler: foundItemsHandler,
                                              parentProgress: nil,
                                              progressHandler)
    }

    /// 재귀적 목록 생성 비동기 Private 메쏘드
    /// - Parameters:
    ///   - path: 목록 생성 경로
    ///   - showHiddenFiles: 숨김 파일 표시 여부. 기본값은 false
    ///   - foundItemsHandler: 중간값 반환 핸들러
    ///   - parentProgress: Foundation.Progress 인스턴스로 부모 진행상황
    ///   - progressHandler: 전체 갯수, 진행 갯수, 진행율 반환. 진행 아이템 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    private func contentsRecursively(path: String,
                                     showHiddenFiles: Bool = false,
                                     foundItemsHandler: (@Sendable (_ contents: [FileItem]) -> Void)? = nil,
                                     parentProgress: Progress? = nil,
                                     _ progressHandler: @escaping ProgressHandler) async -> Result<[FileItem], Error> {
        
        // 누적 아이템
        var recursiveResults = [FileItem]()
        let result = await self.contents(of: path,
                                         showHiddenFiles: showHiddenFiles)
        
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 사용자 취소 발생.")
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }
        
        // 에러 발생 시 종료 처리
        if case let .failure(error) = result {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(path) >> error = \(error.localizedDescription).")
            // 완료 처리
            progressHandler(1, 1, 1, .list, path.lastPathComponent)
            // 에러 반환
            return .failure(error)
        }
        // 아이템 배열 확인
        guard case let .success(items) = result,
              items.count > 0 else {
            // 완료 처리
            progressHandler(1, 1, 1, .list, path.lastPathComponent)
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 내부 아이템이 0개.")
            // 내부 아이템이 없는 경우 빈 디렉토리 에러 처리
            return .failure(Files.Error.emptyDirectory)
        }

        // Create Progress for current directory with totalUnitCount = items.count
        let progress = Progress(totalUnitCount: Int64(items.count))
        // Link to parent progress if available
        if let parent = parentProgress {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 상위 progress에 추가.")
            parent.addChild(progress, withPendingUnitCount: 1)
        }
        
        // 누적 아이템에 추가
        recursiveResults.append(contentsOf: items)
        // 중간 반환
        foundItemsHandler?(items)
        
        // 하위 디렉토리 확인
        let directories: [FileItem] = items.filter { $0.isDirectory }
        guard directories.count > 0 else {
            progress.completedUnitCount = Int64(items.count)
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 하위 디렉토리 없음. 현재 진행 상태 = \(progress.completedUnitCount)/\(progress.totalUnitCount)")
            // 진행 상태 업데이트
            progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, .list, path.lastPathComponent)
            // 성공 종료 처리
            return .success(recursiveResults)
        }
        
        // 디렉토리 갯수를 제외한 files 갯수 단위 완료 처리
        let filesCount = items.count - directories.count
        progress.completedUnitCount = Int64(filesCount)
        EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 파일 확인 완료. 현재 진행 상태 = \(progress.completedUnitCount)/\(progress.totalUnitCount)")
        // 진행 처리 업데이트
        progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, .list, path.lastPathComponent)
        
        do {
            for directory in directories {
                guard Task.isCancelled == false else {
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 사용자 취소 발생.")
                    // 사용자 취소로 중지 처리
                    return .failure(Files.Error.abort)
                }
                
                // 하위 경로 생성
                let subPath = (path as NSString).appendingPathComponent(directory.filename)
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(subPath) >> 추가 >> \(path) = \(progress.completedUnitCount)/\(progress.totalUnitCount)")
                
                let subResults = await self.contentsRecursively(path: subPath,
                                                                showHiddenFiles: showHiddenFiles,
                                                                foundItemsHandler: foundItemsHandler,
                                                                parentProgress: progress) { totalUnitCount, completedUnitCount, fractionCompleted, work, label in
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(subPath) >> 현재 진행 상태 = \(completedUnitCount)/\(totalUnitCount)")
                    // 완료 핸들러 업데이트 with parent's progress fraction
                    progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, work, label)
                }
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 완료 = \(progress.completedUnitCount)/\(progress.totalUnitCount)")
                // 완료 핸들러 업데이트
                progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, .list, path)
                
                // 잦은 접속으로 인한 에러 방지를 위해 0.001 초 대기
                try await Task.sleep(nanoseconds: 1_000_000)
                
                switch subResults {
                    // 성공 시
                case let .success(items):
                    recursiveResults.append(contentsOf: items)
                    continue
                    
                    // 에러 발생 시
                case let .failure(error):
                    if case Files.Error.emptyDirectory = error {
                        // 빈 디렉토리인 경우 패스
                        continue
                    }
                    // 그 동안의 누적 아이템을 무시하고 실패 처리
                    return .failure(error)
                }
            }
            
            // 성공 처리. 누적 아이템 반환.
            return .success(recursiveResults)
        }
        catch {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(path) >> 에러 = \(error.localizedDescription)")
            // 에러 발생
            return .failure(error)
        }
    }
    
    // MARK: - Search Methods
    
    /// 기본 검색 비동기 메쏘드
    /// - Parameters:
    ///   - path: 검색할 경로
    ///   - showHiddenFiles: 감춤 파일 표시 여부. 기본값은 false
    ///   - recursive: 재귀적 검색 여부. true 로 지정하면 하위 폴더의 파일을 재귀적으로 계속 탐색한다. 기본값은 false.
    ///   - query: `NSPredicate`
    ///   - foundItemsHandler: 중간에 발견된 `FileItem` 배열
    ///   - progressHandler: 전체 개수, 진행 개수, 진행율, 진행 아이템명 반환.
    /// - Important: 현재 구조 상, 하위 개수를 포함한 정확한 진행 개수의 파악이 불가능하다. 진행율은 정확하게 파악된다.
    /// - Returns: `Result` 타입으로 `FileItem` 배열 또는 에러 반환.
    public func searchFiles(path: String,
                            showHiddenFiles: Bool = false,
                            recursive: Bool = false,
                            query: NSPredicate,
                            foundItemsHandler: (@Sendable (_ checkItems: [FileItem]) -> Void)?,
                            _ progressHandler: @escaping ProgressHandler) async -> Result<[FileItem], Error> {
        guard recursive == true else {
            // 재귀적 검색이 불필요한 경우
            let result = await self.contents(of: path,
                                             showHiddenFiles: showHiddenFiles)
            switch result {
            case .success(let items):
                let foundItems = items.filter { query.evaluate(with: $0.mapPredicate()) }
                return .success(foundItems)
                
            case .failure(let error):
                return .failure(error)
            }
        }
        
        let result = await self.contentsRecursively(
            path: path,
            showHiddenFiles: showHiddenFiles,
            foundItemsHandler:
                { [query] contents in
                    guard let foundItemsHandler = foundItemsHandler else {
                        return
                    }
                    // 중간 완료 핸들러 반환
                    let foundItems = contents.filter { query.evaluate(with: $0.mapPredicate()) }
                    foundItemsHandler(foundItems)
                },
            progressHandler)
        
        switch result {
            // 성공 시
        case let .success(items):
            guard items.count > 0 else {
                // 빈 디렉토리 에러 반환
                return .failure(Files.Error.emptyDirectory)
            }
            let foundFiles = items.filter { query.evaluate(with: $0.mapPredicate()) }
            return .success(foundFiles)
            
            // 에러 발생 시
        case .failure(_):
            // 그대로 반환 처리
            return result
        }
    }
    
    // MARK: - Upload Methods
    /// 파일 업로드
    /// - Important: 폴더인 경우, 서버에 디렉토리를 생성하기만 한다. 폴더 내용까지 올리려면 `writeFolder` 메쏘드를 사용한다.
    /// - Parameters:
    ///    - originURL: 업로드할 파일 URL.
    ///    - targetPath: 파일이 올라갈 FTP 경로, 업로드할 파일/폴더명까지 포함해야 한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    func write(from originURL: URL,
               to targetPath: String,
               conflictHandler: (@Sendable () async -> Files.Conflict)?,
               _ progressHandler: @escaping ProgressHandler) async -> Result<Bool, Error> {
        return await write(from: originURL.filePath, to: targetPath, conflictHandler: conflictHandler, progressHandler)
    }

    /// 폴더 일괄 업로드
    /// - Important: 폴더 내부의 파일까지 올린다.
    /// - Parameters:
    ///    - localPath: 업로드할 폴더 경로
    ///    - remotePath: 파일이 올라갈 FTP 경로로 폴더명까지 포함해서 지정한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    ///    - progressHandler: 전체 개수, 진행 개수 반환. 진행 아이템 반환.
    /// - Returns: Result 타입으로 성공 또는 에러 반환
    public func writeFolder(_ localPath: String,
                            to remotePath: String,
                            conflictHandler: (@Sendable () async -> Files.Conflict)? = nil,
                            _ progressHandler: @escaping @Sendable ProgressHandler) async -> Result<Bool, Error> {
        guard Task.isCancelled == false else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(localPath) >> 사용자 취소 발생.")
            // 진행 개수 1로 완료 처리
            progressHandler(1, 1, 1, .write, remotePath.lastPathComponent)
            // 사용자 취소로 중지 처리
            return .failure(Files.Error.abort)
        }

        /// 충돌 상태 관리 클래스 (Sendable 클로저 캡처 지원용)
        let conflicResolveState = ConflictResolveState()
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localPath, isDirectory: &isDirectory),
                isDirectory.boolValue else {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(localPath) >> 디렉토리가 아님.")
            // 진행 개수 1로 완료 처리
            progressHandler(1, 1, 1, .error(Files.Error.uploadFileFailed), remotePath.lastPathComponent)
            return .failure(Files.Error.uploadFileFailed)
        }
        
        guard let subPaths = fileManager.enumerator(atPath: localPath)?.allObjects as? [String] else {
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(localPath) >> 내부 파일이 없음. 폴더 생성만 하고 종료.")
            // 진행 개수 1로 완료 처리
            progressHandler(1, 1, 1, .write, remotePath.lastPathComponent)
            return await self.write(from: localPath,
                                    to: remotePath,
                                    conflictHandler: {
                return await conflicResolveState.resolve {
                    await conflictHandler?() ?? .abort
                }
            }, progressHandler)
        }
        
        // 현재 아이템 갯수까지 포함해서 items 갯수에 1을 더한 것을 총 갯수로 간주한다.
        let progress = Progress(totalUnitCount: Int64(subPaths.count + 1))
        // 디렉토리 생성 시도
        let result = await self.write(from: localPath, to: remotePath, conflictHandler: {
            return await conflicResolveState.resolve {
                await conflictHandler?() ?? .abort
            }
        }) { totalUnitCount, completedUnitCount, fractionCompleted, work, label in
            progress.completedUnitCount += 1
            progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, work, label)
        }

        if case let .failure(error) = result {
            EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(remotePath) >> 디렉토리 생성 실패.")
            // 진행 개수 1로 완료 처리
            progressHandler(progress.totalUnitCount, progress.totalUnitCount, 1, .error(error), remotePath.lastPathComponent)
            return .failure(error)
        }
        
        // 디렉토리 생성 성공, 하위 파일 업로드 실행
        // maxConcurrentUploads가 1이면 순차 업로드, 2 이상이면 병렬 업로드
        let maxConcurrent = self.maxConcurrentUploads
        
        if maxConcurrent <= 1 {
            // 순차 업로드 (FTP 등)
            for subPath in subPaths {
                guard Task.isCancelled == false else {
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(subPath) >> 사용자 취소 발생.")
                    // 완료 핸들러 업데이트
                    progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .cancel, remotePath.lastPathComponent)
                    // 사용자 취소로 중지 처리
                    return .failure(Files.Error.abort)
                }

                let localSubPath = localPath.appendingPathComponent(subPath)
                let subProgress = Progress(totalUnitCount: 0)
                progress.addChild(subProgress, withPendingUnitCount: 1)
                let result = await self.write(from: localSubPath, to: remotePath.appendingPathComponent(subPath), conflictHandler: {
                    return await conflicResolveState.resolve {
                        await conflictHandler?() ?? .abort
                    }
                }) { totalUnitCount, completedUnitCount, fractionCompleted, work, label in
                    if totalUnitCount != 0 {
                        subProgress.totalUnitCount = totalUnitCount
                    }
                    subProgress.completedUnitCount = completedUnitCount
#if DEBUG
                     EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 진행율 = \(progress.fractionCompleted)")
#endif
                    // 진행 상태 업데이트
                    progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, work, label)
                }
                if case let .failure(error) = result {
                    EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(localSubPath) >> 하위 경로 파일 업로드 실패.")
                    // 완료 핸들러 업데이트
                    progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .error(error), remotePath.lastPathComponent)
                    return .failure(error)
                }
            }
        } else {
            // 병렬 업로드 (OneDrive, SFTP 등)
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(remotePath) >> 병렬 업로드 시작 (max: \(maxConcurrent))")
            
            // 1. 파일과 디렉토리 분리
            var directories: [String] = []
            var files: [String] = []
            
            for subPath in subPaths {
                let localSubPath = localPath.appendingPathComponent(subPath)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: localSubPath, isDirectory: &isDir), isDir.boolValue {
                    directories.append(subPath)
                } else {
                    files.append(subPath)
                }
            }
            
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 총 \(directories.count)개 디렉토리, \(files.count)개 파일")
            
            // 2. 디렉토리 먼저 순차 생성 (경쟁 조건 방지)
            for directory in directories {
                guard Task.isCancelled == false else {
                    EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(directory) >> 사용자 취소 발생.")
                    progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .cancel, remotePath.lastPathComponent)
                    return .failure(Files.Error.abort)
                }
                
                let localDirPath = localPath.appendingPathComponent(directory)
                let remoteDirPath = remotePath.appendingPathComponent(directory)
                let subProgress = Progress(totalUnitCount: 0)
                progress.addChild(subProgress, withPendingUnitCount: 1)
                
                let result = await self.write(from: localDirPath, to: remoteDirPath, conflictHandler: {
                    return await conflicResolveState.resolve {
                        await conflictHandler?() ?? .abort
                    }
                }) { totalUnitCount, completedUnitCount, fractionCompleted, work, label in
                    if totalUnitCount != 0 {
                        subProgress.totalUnitCount = totalUnitCount
                    }
                    subProgress.completedUnitCount = completedUnitCount
                    progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, work, label)
                }
                
                if case let .failure(error) = result {
                    EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(localDirPath) >> 디렉토리 생성 실패.")
                    progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .error(error), remotePath.lastPathComponent)
                    return .failure(error)
                }
            }
            
            // 3. 파일을 TaskGroup으로 병렬 업로드
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // 동시성 제어용 세마포어
                    var runningTasks = 0
                    var fileIndex = 0
                    
                    // 초기 배치: maxConcurrent만큼 시작
                    while fileIndex < files.count && runningTasks < maxConcurrent {
                        let filePath = files[fileIndex]
                        fileIndex += 1
                        runningTasks += 1
                        // groupTask로 추가
                        addGroupTask(filePath)
                    }
                    
                    // 하나씩 완료되면 새로운 작업 추가
                    while let _ = try await group.next() {
                        runningTasks -= 1
                        
                        // 남은 파일이 있으면 추가
                        if fileIndex < files.count {
                            let filePath = files[fileIndex]
                            fileIndex += 1
                            runningTasks += 1
                            // groupTask로 추가
                            addGroupTask(filePath)
                        }
                    }
                    
                    //-----------------------------------------------------------------------//
                    /// 특정 경로의 업로드 작업을 groupTask로 추가하는 내부 메쏘드
                    func addGroupTask(_ filePath: String) {
                        let localFilePath = localPath.appendingPathComponent(filePath)
                        let remoteFilePath = remotePath.appendingPathComponent(filePath)
                        let subProgress = Progress(totalUnitCount: 0)
                        progress.addChild(subProgress, withPendingUnitCount: 1)
                        
                        group.addTask {
                            guard Task.isCancelled == false else {
                                throw Files.Error.abort
                            }
                            
                            let result = await self.write(from: localFilePath, to: remoteFilePath, conflictHandler: {
                                return await conflicResolveState.resolve {
                                    await conflictHandler?() ?? .abort
                                }
                            }) { totalUnitCount, completedUnitCount, fractionCompleted, work, label in
                                if totalUnitCount != 0 {
                                    subProgress.totalUnitCount = totalUnitCount
                                }
                                subProgress.completedUnitCount = completedUnitCount
#if DEBUG
                                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: [병렬] \(label ?? "Unknown") 진행율 = \(fractionCompleted)")
#endif
                                progressHandler(progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted, work, label)
                            }
                            
                            if case let .failure(error) = result {
                                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(localFilePath) >> 파일 업로드 실패.")
                                throw error
                            }
                        }
                    }
                    //-----------------------------------------------------------------------//
                }
                
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(remotePath) >> 병렬 업로드 완료")
            } catch {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(remotePath) >> 병렬 업로드 중 에러 발생 = \(error.localizedDescription)")
                progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .error(error), remotePath.lastPathComponent)
                return .failure(error)
            }
        }

        // 완료 핸들러 업데이트
        progressHandler(progress.totalUnitCount, progress.totalUnitCount, progress.fractionCompleted, .write, remotePath.lastPathComponent)
        return .success(true)
    }
    
    // MARK: - AsyncStream-based Upload Methods
    
    /// 폴더 일괄 업로드 (AsyncStream 기반)
    /// - Important: 폴더 내부의 파일까지 올린다.
    /// - Parameters:
    ///    - localPath: 업로드할 폴더 경로
    ///    - remotePath: 파일이 올라갈 경로로 폴더명까지 포함해서 지정한다.
    ///    - conflictHandler: 동일한 파일이 있는 경우, 어떻게 할 지 여부를 확인하는 핸들러.
    /// - Returns: `AsyncThrowingStream<Progress, Error>` - 진행 상태를 yield하고 완료 또는 에러 시 종료
    /// - Note: Modern Swift Concurrency API. `for await` 루프로 진행 상태를 소비할 수 있습니다.
    /// - Example:
    /// ```swift
    /// do {
    ///     for try await progress in provider.writeFolder(localPath, to: remotePath) {
    ///         print("진행률: \(progress.fractionCompleted)")
    ///         if let currentItem = progress.userInfo[.currentItemKey] as? String {
    ///             print("현재: \(currentItem)")
    ///         }
    ///     }
    /// } catch {
    ///     print("업로드 실패: \(error)")
    /// }
    /// ```
    public func writeFolder(_ localPath: String,
                            to remotePath: String,
                            conflictHandler: (@Sendable () async -> Files.Conflict)? = nil) -> AsyncThrowingStream<Progress, Error> {
        
        return AsyncThrowingStream { continuation in
            Task {
                // Progress 객체 생성
                let mainProgress = Progress(totalUnitCount: 1)
                
                // 기존 클로저 기반 API를 호출하고 progress를 스트림으로 변환
                let result = await self.writeFolder(localPath, 
                                                    to: remotePath, 
                                                    conflictHandler: conflictHandler) { total, current, fraction, work, label in
                    // Progress 객체 업데이트
                    mainProgress.totalUnitCount = total
                    mainProgress.completedUnitCount = current
                    
                    // 현재 아이템을 userInfo에 저장
                    if let label {
                        mainProgress.setUserInfoObject(label, forKey: .fileURLKey)
                    }
                    
                    // Progress 객체를 yield
                    continuation.yield(mainProgress)
                }
                
                // 결과에 따라 스트림 종료
                switch result {
                case .success:
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    
    // MARK: - Helper Methods
    
    /// 특정 경로의 URL을 반환
    public func url(of path: String) -> URL {
        if let baseURL = baseURL {
            return baseURL.appendingPathComponent(path)
        } else {
            // File URL로 간주하고 경로 자체로 초기화해서 반환한다
            return URL(fileURLWithPath: path)
        }
    }

    // MARK: - URLCache Method
    
    /// URLCache 사용 가능 여부
    public var canUseURLCache: Bool {
        return urlCache != nil
    }
    
    /// URLRequest용 URL 작성
    /// - Important: offset / length 를 추가해 사용할 때 "?offset=..."이란 식으로 사용하면 문제가 발생한다. 따라서 `URLComponent`를 이용해 작성하도록 한다.
    /// - Parameters:
    ///   - path: 경로.
    ///   - offset: Offset 값. 기본값은 0.
    ///   - length: Lengt 값. 기본값은 0.
    /// - Returns: `URL` 반환. 실패 시 널값 반환.
    public func requestURL(at path: String, offset: Int64 = 0, length: Int64 = 0) -> URL? {
        return baseURL?.requestURL(at: path, offset: offset, length: length)
    }

    /// URLCache에 데이터 생성 후 반환
    /// - `URLCache` 가 NIL이 아닌 경우, 관련 메쏘드에서 호출한다.
    /// - Parameters:
    ///   - request: `URLRequest`로 가져올 데이터를 찾는다.
    ///   - validatingCache: 캐쉬 유효성 확인 여부. true 로 지정하면 헤더 값을 가져와 비교해, 변경이 발생한 경우에는 데이터를 새로 내려받는다. 단, FTP, SFTP 등은 유효성 검사를 true 로 지정한 경우, 무조건 캐쉬를 업데이트하게 된다.
    /// - Returns: Result 타입으로 Data와 URLResponse 튜플, 또는 에러 반환.
    func returnCachedData(with request: URLRequest, validatingCache: Bool) async -> Result<(Data, URLResponse), Error> {
        guard let urlCache = self.urlCache,
              let cachedResponse = urlCache.cachedResponse(for: request) else {
            return .failure(Files.Error.accessToURLCacheFailed)
        }
        
        guard !validatingCache else {
            // 유효성 검사가 필요한 경우
            // FTP, SFTP 등은 유효성 검사를 true 로 지정한 경우, 무조건 캐쉬를 업데이트해야 한다.
            return .failure(Files.Error.updateURLCacheIsNeeded)
        }
        
        // 유효성이 확인된 경우 또는 유효성 검사 생략 시 데이터 반환
        return .success((cachedResponse.data, cachedResponse.response))
    }
    
    /// URLCache에 데이터 저장
    /// - Parameters:
    ///   - data: 캐쉬로 저장할 데이터.
    ///   - url: 키 `URL`.
    ///   - request: `URLRequest`를 지정.
    ///   - storagePolicy: .allowed 로 지정.
    func saveCacheData(_ data: Data,
                       for url: URL,
                       with request: URLRequest,
                       storagePolicy: URLCache.StoragePolicy = .allowed) async {
        guard self.canUseURLCache else {
            return
        }
        // 캐쉬 데이터 저장
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=2592000"])!
        let cachedResponse = CachedURLResponse(response: response, data: data, userInfo: nil, storagePolicy: storagePolicy)
        self.urlCache?.storeCachedResponse(cachedResponse, for: request)
    }
    
    /// 특정 경로의 캐쉬 제거
    /// - Important: `HTTPProviderable`을 상속받지 않은 FileProvider에서만 사용 가능하다.
    /// OneDriveFileProvider, WebDAVFileProvider는 자체적으로 URLRequest를 사용해 캐쉬를 제거한다.
    func removeCache(of path: String) {
        let url = url(of: path)
        urlCache?.removeCachedResponse(for: URLRequest.createNoneHTTPRequest(url))
    }
    /// 특정 경로의 캐쉬 이동
    /// - Important: `HTTPProviderable`을 상속받지 않은 FileProvider에서만 사용 가능하다.
    /// OneDriveFileProvider, WebDAVFileProvider는 자체적으로 URLRequest를 사용해 캐쉬를 이동시키다.
    /// - Parameters:
    ///   - originPath: 원본 경로.
    ///   - targetPath: 이동 경로.
    ///   - storagePolicy: 캐쉬 저장 정책. 기본값은 `allowed`.
    /// - Returns: 성공 여부 반환.
    @discardableResult
    func moveCache(from originPath: String, to targetPath: String, storagePolicy: URLCache.StoragePolicy = .allowed) -> Bool {
        let originURL = url(of: originPath)
        let targetURL = url(of: targetPath)
        return urlCache?.moveNoneHTTPCache(from: originURL, to: targetURL, storagePolicy: storagePolicy) ?? false
    }

    // MARK: - Resolve Conflict
    
    /// 파일과의 충돌 해결을 위해 사용자 확인을 묻는 내부 메쏘드
    /// - 파일 충돌이 발생하는 경우, 사용자에게 덮어쓰기/병합/건너뛰기 여부를 확인하는데, 이를 위해 사용되는 내부 메쏘드
    /// - Parameters:
    ///   - isDirectory: 충돌이 발생한 파일이 디렉토리인지 여부.
    ///   - conflictHandler: 덮어쓰기/병합/거너뛰기 확인용 완료 핸들러.
    ///   - removeHanlder: 덮어쓰기 시, 기존 파일 제거를 실행하는 완료 핸들러.
    /// - Returns: Result 타입으로 기존 파일을 삭제하는 조건이라면 true를 반환한다.
    /// 기존 파일이 있지만 병합/건너뛰기 발생 시에는 false를 반환한다.
    /// 충돌이 있는데도 사용자 확인을 받지 못한 경우, 또는 삭제 중 문제가 발생하면 에러를 반환한다.
    func resolveFileConflict(isDirectory: Bool,
                             _ conflictHandler: @Sendable () async -> Files.Conflict,
                             removeHanlder: () async -> Result<Bool, Error>) async -> Result<Bool, Error> {
        // 사용자 확인 진행
        switch await conflictHandler() {
            // 병합 조건
        case .merge:
            // 기존 피일이 폴더인 경우
            if isDirectory {
                // 폴더 제거나 추가 없이 건너뛰도록 한다.
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 기존 폴더와의 병합, 건너뛰기를 실행합니다.")
                // false를 성공값으로 반환한다.
                return .success(false)
            }
            // 파일인 경우, 덮어쓰기로 처리한다.
            else {
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 기존 파일과의 병합, 덮어쓰기를 위해 기존 파일을 제거합니다.")
                return await removeHanlder()
            }
            
            // 덮어쓰기 조건
        case .overwrite:
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 덮어쓰기를 위해 기존 파일 및 폴더를 제거합니다.")
            return await removeHanlder()

            // 건너뛰기 조건
        case .skip:
            // false를 성공값으로 반환한다.
            return .success(false)
            
            // 취소 처리
        case .abort:
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: 사용자가 작업을 취소 처리했습니다.")
            return .failure(Files.Error.abort)
        }
    }

    /// 특정 로컬 URL의 충돌 확인
    /// - 서버로부터의 다운로드 또는 로컬 드라이브 내의 이동/복사 시 파일 충돌이 발생하는 경우, 사용자에게 덮어쓰기/병합/건너뛰기 여부를 확인한다.
    /// - Parameters:
    ///   - url: 파일 충돌 여부 확인 `URL`.
    ///   - conflictHandler: 덮어쓰기/병합/거너뛰기 확인용 완료 핸들러.
    /// - Returns: Result 타입으로 충돌 파일이 없거나 기존 파일을 삭제하는 데 성공하면 true를 반환한다.
    /// 기존 파일이 있지만 병합/건너뛰기 발생 시에는 false를 반환한다.
    /// 충돌이 있는데도 사용자 확인을 받지 못한 경우, 또는 삭제 중 문제가 발생하면 에러를 반환한다.
    internal func resolveFileConflict(ofLocalURL url: URL, _ conflictHandler: (@Sendable () async -> Files.Conflict)?) async -> Result<Bool, Error> {
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.filePath, isDirectory: &isDirectory) else {
            // 파일이 없는 경우 성공 반환
            return .success(true)
        }
        
        guard let conflictHandler else {
            // 충돌 여부를 사용자에게 확인하지 않는 경우
            return .failure(Files.Error.disallowOverwrite)
        }

        // 확인 결과
        return await resolveFileConflict(isDirectory: isDirectory.boolValue, conflictHandler) {
            // 사용자 덮어쓰기 승인 시
            EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(url.filePath) >> 기존 파일을 제거합니다.")
            do {
                // 파일이 존재하는 경우
                // 사용자 덮어쓰기 승인 시
                EdgeLogger.shared.networkLogger.debug("\(#file):\(#function) :: \(url.filePath) >> 기존 파일을 제거합니다.")
                // 해당 파일 제거
                try fileManager.removeItem(at: url)
                return .success(true)
            }
            catch {
                EdgeLogger.shared.networkLogger.error("\(#file):\(#function) :: \(url.filePath) >> 에러 발생 = \(error.localizedDescription).")
                return .failure(error)
            }
        }
    }
}

// MARK: - Helper Classes -

/// 충돌 상태 관리 Actor (race condition 방지용)
/// - 최초 호출만 conflictHandler를 실행하고, 이후 호출은 결과를 기다렸다가 동일한 값을 반환한다.
actor ConflictResolveState {

    private var resolvedValue: Files.Conflict? = nil
    private var isResolving = false
    private var pendingContinuations: [CheckedContinuation<Files.Conflict, Never>] = []

    /// 충돌 해결 메쏘드
    /// - 최초 호출 시 handler를 실행하고, 이후 호출은 결과를 기다린다.
    func resolve(using handler: @Sendable () async -> Files.Conflict) async -> Files.Conflict {
        // 이미 결정된 경우 즉시 반환
        if let resolvedValue {
            return resolvedValue
        }
        // 다른 Task가 이미 처리 중인 경우 → 결과를 기다림
        if isResolving {
            return await withCheckedContinuation { continuation in
                pendingContinuations.append(continuation)
            }
        }
        // 최초 호출 → 실제 처리
        isResolving = true
        let result = await handler()
        resolvedValue = result
        // 대기 중인 모든 Task에 결과 전달
        for continuation in pendingContinuations {
            continuation.resume(returning: result)
        }
        pendingContinuations.removeAll()
        return result
    }
}


// MARK: - Legacy CompletionHandler Wrappers -
extension FileProviderable {
    /// FileItem 생성 (Completion Handler Wrapper)
    public func makeItem(of path: String, _ completionHandler: @escaping @Sendable (Result<FileItem, Error>) -> Void) {
        Task {
            do {
                let item = try await self.makeItem(of: path)
                completionHandler(.success(item))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    /// 특정 path 내부의 아이템을 목록으로 가져오는 메쏘드 (Completion Handler Wrapper)
    public func contents(of path: String, showHiddenFiles: Bool, _ completionHandler: @escaping @Sendable (Result<[FileItem], Error>) -> Void) {
        Task {
            let result = await self.contents(of: path, showHiddenFiles: showHiddenFiles)
            completionHandler(result)
        }
    }

    /// 특정 경로 파일의 크기를 구한다 (Completion Handler Wrapper)
    public func fileSize(of path: String, _ completionHandler: @escaping @Sendable (Result<UInt64, Error>) -> Void) {
        Task {
            let result = await self.fileSize(of: path)
            completionHandler(result)
        }
    }

    /// 특정 경로가 디렉토리인지 여부를 반환하는 메쏘드 (Completion Handler Wrapper)
    public func isDirectory(of path: String, _ completionHandler: @escaping @Sendable (Bool) -> Void) {
        Task {
            let result = await self.isDirectory(of: path)
            completionHandler(result)
        }
    }

    /// 특정 경로의 전체 Data를 반환 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func data(of path: String, _ completionHandler: @escaping @Sendable (Result<Data, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.data(of: path) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 특정 경로의 특정 영역의 Data를 반환 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func data(of path: String, offset: Int64, length: Int64, _ completionHandler: @escaping @Sendable (Result<Data, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.data(of: path, offset: offset, length: length) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 특정 경로의 파일을 로컬 URL에 다운로드 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func download(from path: String, toLocalFolder localFolder: URL, conflictHandler: (@Sendable () async -> Files.Conflict)?, _ completionHandler: @escaping @Sendable (Result<URL, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.download(from: path, toLocalFolder: localFolder, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 특정 `FileItem` 제거 (Completion Handler Wrapper)
    public func remove(_ item: FileItem, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        Task {
            let result = await self.remove(item)
            completionHandler(result)
        }
    }

    /// 특정 경로의 파일 제거 (Completion Handler Wrapper)
    public func remove(of path: String, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        Task {
            let result = await self.remove(of: path)
            completionHandler(result)
        }
    }

    /// 파일 이동 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func move(from originPath: String, to targetPath: String, conflictHandler: (@Sendable () async -> Files.Conflict)?, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.move(from: originPath, to: targetPath, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 파일명 변경 (Completion Handler Wrapper)
    public func rename(in parentPath: String, from oldFilename: String, to newFilename: String, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        Task {
            let result = await self.rename(in: parentPath, from: oldFilename, to: newFilename)
            completionHandler(result)
        }
    }

    /// 파일 업로드 (originPath 기준) (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func write(from originPath: String, to targetPath: String, conflictHandler: (@Sendable () async -> Files.Conflict)?, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.write(from: originPath, to: targetPath, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 파일 업로드 (Data 기준) (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func write(from data: Data, to targetPath: String, conflictHandler: (@Sendable () async -> Files.Conflict)?, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.write(from: data, to: targetPath, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 파일 업로드 (originURL 기준) (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func write(from originURL: URL, to targetPath: String, conflictHandler: (@Sendable () async -> Files.Conflict)?, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.write(from: originURL, to: targetPath, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 재귀적 목록 생성 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func contentsRecursively(path: String, showHiddenFiles: Bool = false, foundItemsHandler: (@Sendable (_ contents: [FileItem]) -> Void)? = nil, _ completionHandler: @escaping @Sendable (Result<[FileItem], Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.contentsRecursively(path: path, showHiddenFiles: showHiddenFiles, foundItemsHandler: foundItemsHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 기본 검색 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func searchFiles(path: String, showHiddenFiles: Bool = false, recursive: Bool = false, query: NSPredicate, foundItemsHandler: (@Sendable (_ checkItems: [FileItem]) -> Void)?, _ completionHandler: @escaping @Sendable (Result<[FileItem], Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.searchFiles(path: path, showHiddenFiles: showHiddenFiles, recursive: recursive, query: query, foundItemsHandler: foundItemsHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }

    /// 폴더 일괄 업로드 (Completion Handler Wrapper)
    /// - Returns: 진행 상태를 추적하는 `Progress` 객체
    @discardableResult
    public func writeFolder(_ localPath: String, to remotePath: String, conflictHandler: (@Sendable () async -> Files.Conflict)? = nil, _ completionHandler: @escaping @Sendable (Result<Bool, Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            let result = await self.writeFolder(localPath, to: remotePath, conflictHandler: conflictHandler) { total, completed, _, _, label in
                progress.totalUnitCount = max(total, 1)
                progress.completedUnitCount = completed
            }
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(result)
        }
        return progress
    }
}


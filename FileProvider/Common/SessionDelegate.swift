//  SessionDelegate.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/13/25.
//

import Foundation

import CommonLibrary

enum SessionError: LocalizedError {
    case unknown
}

// MARK: - Task State Actor -
/// 작업 상태 Actor
/// - 작업 종료 연속성은 Generic으로 지정한다. 보통 다운로드는 URL, 업로드는 Data 로 지정한다.
fileprivate actor TaskState<HTTPProvider: HTTPProviderable, ResultType: Sendable> {
    
    // MARK: - Properties
    /// Parent Provider
    private weak var provider: HTTPProvider?
    /// 진행 상태 연속성
    var progressContinuation: ProgressContinuation?
    /// 작업 종료 연속성
    var resultContinuation: ResultContinuation<ResultType>?
    /// 전체 크기 (업로드 시 사용)
    fileprivate var totalSize: Int64
    // MARK: Finish Values
    /// 작업 종료 값
    fileprivate var resultValue: ResultType?
    /// Data (서버 데이터)
    private var data: Data?
    /// response (서버 Response)
    private var response: URLResponse?
    /// 작업 종료 여부
    private var isFinished = false
    /// 서버 응답 확인 여부 (업로드 시 2xx 응답 후에만 true)
    private var isServerConfirmed = false
    /// 버퍼링된 진행 상태 (isServerConfirmed가 false일 때 저장, 최신 값만 유지)
    private var bufferedProgress: (total: Int64, progress: Int64)? = nil
    
    // MARK: - Initialization
    /// 초기화
    /// - Parameters:
    ///   - provider: `HTTPProvider`. 널값 지정 가능.
    ///   - progressContinuation: 진행 상태 연속성.
    ///   - resultContinuation: 작업 종료 연속성. Generic 으로 지정한다.
    ///   - totalSize: 파일 전체 크기. 기본값은 0. 업로드 시에는 반드시 이 값을 지정한다.
    fileprivate init(_ provider: HTTPProvider?,
                     progressContinuation: ProgressContinuation? = nil,
                     resultContinuation: ResultContinuation<ResultType>? = nil,
                     totalSize: Int64 = 0) {
        self.provider = provider
        self.progressContinuation = progressContinuation
        self.resultContinuation = resultContinuation
        self.totalSize = totalSize
    }
    /// 진행 상태 연속성 지정
    fileprivate func setProgressContinuation(_ continuation: ProgressContinuation?) {
        self.progressContinuation = continuation
    }
    /// 작업 종료 연속성 지정
    fileprivate func setResultContinuation(_ continuation: ResultContinuation<ResultType>?) {
        self.resultContinuation = continuation
    }
    
    // MARK: - Methods
    /// 진행 상태 연속성 갱신
    /// - Important: 외부에서 `progressContinuation` 를 직접 불러 yield를 실행하면 정상적으로 실행되지 않는다.
    /// `progressContinuation`은 struct로 actor 에 저장되어 있고, 외부에서 부르면 새로운 struct 로 호출되기 때문이다.
    fileprivate func yieldProgress(total: Int64 = -1, progress: Int64) {
        guard let progressContinuation else {
            return
        }
        
        // URLSession은 인증 재시도(401 -> retry) 시 누적 바이트를 보고한다.
        // 예: 첫 시도에서 17MB 업로드 완료 + 재시도에서 17MB = totalBytesExpectedToSend가 34MB로 표시됨
        // totalSize (실제 파일 크기)를 기준으로 오프셋을 계산하여 현재 시도의 진행률만 보고한다.
        
        let reportedTotal = total == -1 ? totalSize : total
        var adjustedProgress = progress
        var adjustedTotal = totalSize // 항상 실제 파일 크기 사용
        
        // reportedTotal이 totalSize보다 크면 인증 재시도가 발생한 것
        // 오프셋 = reportedTotal - totalSize (이전 사이클에서 전송된 바이트)
        if reportedTotal > totalSize && totalSize > 0 {
            let offset = reportedTotal - totalSize
            adjustedProgress = progress - offset
        }
        
        // 음수 방지
        if adjustedProgress < 0 { adjustedProgress = 0 }
        if adjustedTotal <= 0 { adjustedTotal = totalSize }
        
        // 서버 확인 전이면 최신 값으로 덮어쓰기, 확인 후에만 바로 발행
        if isServerConfirmed {
            progressContinuation.yield((adjustedTotal, adjustedProgress))
        } else {
            bufferedProgress = (total: adjustedTotal, progress: adjustedProgress)
        }
    }
    
    /// 서버 응답 확인 후 버퍼된 진행 상태 발행
    fileprivate func confirmAndFlushProgress() {
        guard let progressContinuation else { return }
        isServerConfirmed = true
        // 버퍼된 최신 진행 상태 발행
        if let buffered = bufferedProgress {
            progressContinuation.yield((buffered.total, buffered.progress))
            bufferedProgress = nil
        }
    }

    /// 버퍼 초기화 (인증 실패/재시도 시 호출)
    fileprivate func clearBuffer() {
        bufferedProgress = nil
        isServerConfirmed = false
        response = nil  // 재시도 시작 시 이전 에러 응답 초기화
    }
    /// 진행 상태 연속성 종료
    fileprivate func finishProgressContinuation() {
        self.progressContinuation?.finish()
    }
    /// 진행 상태 초기화 (인증 재시도 시 호출)
    fileprivate func resetProgress() {
        self.clearBuffer()
    }
    /// 작업 종료 연속성 종료
    /// - Parameter result: Result 타입으로 성공 시 결과값을, 실패 시 에러를 지정한다.
    fileprivate func finishResultContinuation(with result: Result<ResultType, Error>) {
        guard isFinished == false,
            let resultContinuation else {
            return
        }
        
        // scope 종료 시
        defer {
            // 작업 종료
            isFinished = true
        }
        
        switch result {
            // 성공 시
        case .success(let value): resultContinuation.resume(returning: value)
            // 실패 시
        case .failure(let error): resultContinuation.resume(throwing: error)
        }
    }
    
    // MARK: - Append Value
    /// 서버 데이터 대입
    fileprivate func appendServerData(_ data: Data) {
        self.data = data
    }
    /// 서버 response 대입
    fileprivate func appendServerResponse(_ response: URLResponse) {
        self.response = response
    }
    /// 작업 종료값 대입
    fileprivate func appendResult(_ result: ResultType) {
        self.resultValue = result
    }
    
    // MARK: - Finish
    /// 지정된 작업 종료값으로 종료 처리
    fileprivate func finishResultContinuation() async {
        guard isFinished == false,
              let resultContinuation else {
            return
        }
        
        // scope 종료 시
        defer {
            // 작업 종료
            isFinished = true
        }
        
        // 먼저 response 가 널값인지 확인한다. 에러가 발생하지 않았다면 response는 널값이다.
        // 그 다음, resultValue를 확인한다.
        guard response == nil else {
            // 에러 발생 시
            // 에러 처리를 진행한다.
            var error: Error
            if let provider,
               let response,
               let errorCode = (response as? HTTPURLResponse)?.statusCode,
               let httpErrorCode = HTTPErrorCode(rawValue: errorCode) {
                error = await provider.serverError(with: httpErrorCode, path: nil, data: self.data)
            }
            else {
                // 알 수 없는 에러로 처리
                error = SessionError.unknown
            }
            resultContinuation.resume(throwing: error)
            return
        }
        
        guard let resultValue else {
            // 알 수 없는 에러로 처리
            resultContinuation.resume(throwing: SessionError.unknown)
            return
        }
        // 성공 시
        resultContinuation.resume(returning: resultValue)
    }
}

// MARK: - Session Delegate Actor -
/// URLSession 델리게이트 메쏘드를 다루는 Actor
public actor SessionDelegate<HTTPProvider: HTTPProviderable>: NSObject,
                                                              URLSessionDataDelegate,
                                                              URLSessionDownloadDelegate,
                                                              URLSessionTaskDelegate,
                                                              URLSessionStreamDelegate {
    /// Parent Provider
    private weak var provider: HTTPProvider?
    /// Credential
    private var credential: URLCredential

    /// 다운로드 진행 상태/작업 종료 연속성 딕셔너리
    private var downloadTaskContinuations = [Int : TaskState<HTTPProvider, URL>]()
    /// 업로드 진행 상태/작업 종료 연속성 딕셔너리
    private var uploadTaskContinuations = [Int : TaskState<HTTPProvider, Data>]()

    // MARK: - Initialization
    /// 초기화
    /// - Parameters:
    ///   - provider: `HTTPProvider`
    ///   - credential: `URLCredential`
    init(provider: HTTPProvider, credential: URLCredential) {
        self.provider = provider
        self.credential = credential
    }

    // MARK: - Continuations Methods
    // MARK: Downloads
    /// 다운로드 연속성 추가
    internal func addDownloadContinuations(forTask task: URLSessionTask,
                                           progress: ProgressContinuation,
                                           result: ResultContinuation<URL>) async {
        guard let state = downloadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            downloadTaskContinuations[task.taskIdentifier] = .init(provider, progressContinuation: progress, resultContinuation: result)
            return
        }
        if await state.progressContinuation == nil {
            await state.setProgressContinuation(progress)
        }
        if await state.resultContinuation == nil {
            await state.setResultContinuation(result)
        }
    }
    /// 다운로드 진행 상태 연속성 추가
    internal func addDownloadProgressContinuations(forTask task: URLSessionTask,
                                                   progress: ProgressContinuation) async {
        guard let state = downloadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            downloadTaskContinuations[task.taskIdentifier] = .init(provider, progressContinuation: progress)
            return
        }
        if await state.progressContinuation == nil {
            await state.setProgressContinuation(progress)
        }
    }
    /// 다운로드 작업 종료 연속성 추가
    internal func addDownloadResultContinuations(forTask task: URLSessionTask,
                                                 result: ResultContinuation<URL>) async {
        guard let state = downloadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            downloadTaskContinuations[task.taskIdentifier] = .init(provider, resultContinuation: result)
            return
        }
        if await state.resultContinuation == nil {
            await state.setResultContinuation(result)
        }
    }
    /// 다운로드 연속성 삭제
    internal func removeDownloadContinuations(forTask task: URLSessionTask) {
        downloadTaskContinuations.removeValue(forKey: task.taskIdentifier)
    }
    
    // MARK: Uploads
    /// 업로드 연속성 추가
    /// - Parameters:
    ///   - task: 지정할 `URLSessionTask`.
    ///   - progress: 진행 상태 연속성.
    ///   - result: 완료 연속성.
    ///   - totalSize: 파일 전체 크기.
    internal func addUploadContinuations(forTask task: URLSessionTask,
                                         progress: ProgressContinuation,
                                         result: ResultContinuation<Data>,
                                         totalSize: Int64) async {
        guard let state = uploadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            uploadTaskContinuations[task.taskIdentifier] = .init(provider, progressContinuation: progress, resultContinuation: result, totalSize: totalSize)
            return
        }
        if await state.progressContinuation == nil {
            await state.setProgressContinuation(progress)
        }
        if await state.resultContinuation == nil {
            await state.setResultContinuation(result)
        }
    }
    /// 업로드 진행 상태 연속성 추가
    internal func addUploadProgressContinuations(forTask task: URLSessionTask,
                                                 progress: ProgressContinuation) async {
        guard let state = uploadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            uploadTaskContinuations[task.taskIdentifier] = .init(provider, progressContinuation: progress)
            return
        }
        if await state.progressContinuation == nil {
            await state.setProgressContinuation(progress)
        }
    }
    /// 업로드 작업 종료 연속성 추가
    internal func addUploadResultContinuations(forTask task: URLSessionTask,
                                               result: ResultContinuation<Data>) async {
        guard let state = uploadTaskContinuations[task.taskIdentifier] else {
            // 초기화 실행
            uploadTaskContinuations[task.taskIdentifier] = .init(provider, resultContinuation: result)
            return
        }
        if await state.resultContinuation == nil {
            await state.setResultContinuation(result)
        }
    }
    /// 업로드 연속성 삭제
    internal func removeUploadContinuations(forTask task: URLSessionTask) {
        uploadTaskContinuations.removeValue(forKey: task.taskIdentifier)
    }
    
    // MARK: - Delegate Method
    // 서버에서 최초로 응답 받은 경우에 호출(상태코드 처리)
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        // 업로드 작업인 경우
        if let continuations = uploadTaskContinuations[dataTask.taskIdentifier] {
            // 성공 여부 확인
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // 에러 발생 (401 등), 버퍼 초기화 및 response를 지정한다.
                await continuations.clearBuffer()
                await continuations.appendServerResponse(response)
                // 일단 진행을 계속한다.
                return .allow
            }
            // 성공 시, 버퍼된 진행 상태를 모두 발행
            await continuations.confirmAndFlushProgress()
        }
        // 그 외의 경우
        return .allow
    }
    
    /// 업로드 상태 변경 시 호출
    nonisolated public func urlSession(_ session: URLSession,
                                       task: URLSessionTask,
                                       didSendBodyData bytesSent: Int64,
                                       totalBytesSent: Int64,
                                       totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else {
            return
        }
        
        Task {
            // total 값을 명시적으로 전달 (다운로드와 동일한 방식)
            await uploadTaskContinuations[task.taskIdentifier]?.yieldProgress(total: totalBytesExpectedToSend, progress: totalBytesSent)
        }
    }
    /// 서버로부터 발생한 Response Data 수신
    /// - 서버에서 데이터를 받을 때(이를테면 업로드 등)마다 반복적으로 호출된다
    nonisolated public func urlSession(_ session: URLSession,
                                       dataTask: URLSessionDataTask,
                                       didReceive data: Data) {
        Task {
            // 업로드 연속성 확인 시
            if let uploadTaskState = await uploadTaskContinuations[dataTask.taskIdentifier] {
                // 만일을 위해 data를 추가한다.
                await uploadTaskState.appendResult(data)
            }
        }
    }
    
    /// 다운로드 상태 변경 시 호출
    nonisolated public func urlSession(_ session: URLSession,
                                       downloadTask: URLSessionDownloadTask,
                                       didWriteData bytesWritten: Int64,
                                       totalBytesWritten: Int64,
                                       totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        
        Task {
            await downloadTaskContinuations[downloadTask.taskIdentifier]?.yieldProgress(total: totalBytesExpectedToWrite, progress: totalBytesWritten)
        }
    }
    
    /// 다운로드 종료 시 호출
    /// - Important: 여기서 생성된 임시 파일은 `HTTPProviderable`애서 삭제해야만 한다.
    nonisolated public func urlSession(_ session: URLSession,
                                       downloadTask: URLSessionDownloadTask,
                                       didFinishDownloadingTo location: URL) {
        // 임시 파일 경로를 생성하고, 파일을 복사해 둔다.
        // 해당 델리게이트가 종료되면 다른 쓰레드에서 `HTTPProviderable`에서 접근하기 전에 파일이 즉시 삭제되기 때문이다.
        // 복사된 파일은 추후 `HTTPProviderable` 에서 삭제해야 한다.
        let fileManager = FileManager.default
        let newLocation = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.moveItem(at: location, to: newLocation)
        }
        catch {
             Task {
                 if let continuations = await self.downloadTaskContinuations[downloadTask.taskIdentifier] {
                     await continuations.finishResultContinuation(with: .failure(error))
                     await continuations.finishProgressContinuation()
                     await self.removeDownloadContinuations(forTask: downloadTask)
                 }
             }
             return
        }

        Task {
            guard let continuations = await self.downloadTaskContinuations[downloadTask.taskIdentifier] else {
                return
            }
            // 다운로드 작업 연속성 종료 처리
            // 이동시킨 파일 경로를 반환한다.
            await continuations.finishResultContinuation(with: .success(newLocation))
            await continuations.finishProgressContinuation()
            // 다운로드 작업 연속성 제거
            await removeDownloadContinuations(forTask: downloadTask)
        }
    }
    
    /// 작업 종료 시 호출
    nonisolated public func urlSession(_ session: URLSession,
                                       task: URLSessionTask,
                                       didCompleteWithError error: Error?) {
        Task {
            // 다운로드 작업 연속성 확인
            if let continuations = await self.downloadTaskContinuations[task.taskIdentifier] {
                if let error {
                    // 에러 발생 시, 에러 처리
                    await continuations.finishResultContinuation(with: .failure(error))
                }
                await continuations.finishProgressContinuation()
                await self.removeDownloadContinuations(forTask: task)
            }
            // 업로드 작업 연속성 확인
            else if let continuations = await self.uploadTaskContinuations[task.taskIdentifier] {
                if let error {
                    await continuations.finishResultContinuation(with: .failure(error))
                }
                else {
                    if await continuations.resultValue != nil {
                        // 결과값 Data가 지정된 경우, 종료 처리
                        await continuations.finishResultContinuation()
                    }
                    else {
                        // 결과값 Data를 `urlSession(_:,dataTask: URLSessionDataTask:)` 델리게이트 메쏘드에서 받지 못한 경우
                        // 알 수 없는 에러로 종료 처리한다.
                        await continuations.finishResultContinuation(with: .failure(SessionError.unknown))
                    }
                }
                await continuations.finishProgressContinuation()
                await self.removeUploadContinuations(forTask: task)
            }
        }
    }
    
    // MARK: Session Delegate Method
    /// 서버 접근에 대해 세션 레벨의 인증 요구
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        return await self.authenticate(didReceive: challenge, forTask: task)
    }
    /// 서버 접근에 대해 세션 레벨의 인증 요구
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        return await self.authenticate(didReceive: challenge)
    }
    
    /// 인증 처리 Private 메쏘드
    private func authenticate(didReceive challenge: URLAuthenticationChallenge, forTask task: URLSessionTask? = nil) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // 업로드 작업인 경우, 인증 재시도 시 진행 상태 초기화
        // 이렇게 하면 첫 번째 (실패한) 시도의 진행률이 표시되지 않음
        if let task,
           let uploadState = uploadTaskContinuations[task.taskIdentifier] {
            await uploadState.resetProgress()
        }
        
        switch challenge.previousFailureCount {
        case 0...1:
            return (.useCredential, self.credential)
        default:
            return (.performDefaultHandling, nil)
        }
    }
}

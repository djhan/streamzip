//
//  StreamZipArchive.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

// MARK: - Protocol -
/**
 StreamZip에서 데이터를 전송받기 위해 사용하는 프로토콜
 */
protocol StreamZipTransferConvertible: class {
    /**
     특정 URL의 FileLength를 구하는 메쏘드
     - 완료 핸들러로 FileLength를 반환
     - Parameters:
        - url: `URL`
        - completion: `StreamZipFileLengthCompletion` 완료 핸들러
     */
    func getFileLength(at url: URL, completion: StreamZipFileLengthCompletion)
    
    /**
     특정 URL의 특정 범위 데이터를 가져오는 메쏘드
     - Parameters:
        - url: `URL`
        - range: 데이터를 가져올 범위
        - completion: `StreamZipRequestCompletion` 완료 핸들러
     */
    func request(at url: URL, range: ClosedRange<UInt>, completion: StreamZipRequestCompletion)
}

// MARK: - Typealiases -

/// Request 완료 핸들러
typealias StreamZipRequestCompletion = (_ data: Data?, _ length: UInt, _ error: Error?) -> Void

/**
 FileLength 완료 핸들러
 - Parameters:
    - fileLength: 파일 길이. `UInt`
    - error: 에러. 옵셔널
 */
typealias StreamZipFileLengthCompletion = (_ fileLength: UInt, _ error: Error?) -> Void
/**
 Archive 해제 완료 핸들러
 - Parameters:
    - fileLength: 파일 길이. `UInt`
    - entries: `StreamZipEntry` 배열. 옵셔널
    - error: 에러. 옵셔널
 */
typealias StreamZipArchiveCompletion = (_ fileLength: UInt, _ entries: [entry]?, _ error: Error?) -> Void
/**
 Entry 생성 완료 핸들러
 - Parameters:
    - entry: `StreamZipEntry`
    - error: 에러. 옵셔널
 */
typealias StreamZipFileCompletion = (_ entry: StreamZipEntry, _ error: Error?) -> Void

// MARK: - Stream Zip Archive Class -
class StreamZipArchive {
    
    // MARK: - Properties

    /**
     StreamZipTransferConvertible 프로토콜을 따르는 delegate 오브젝트
     */
    weak var delegate: StreamZipTransferConvertible?
    
    /// 파일 길이
    var fileLength: UInt = 0
    
    // MARK: - Initialization

    
    // MARK: - Methods
    
    /**
     특정 URL
     */
    func fetch(_ url: URL, completion: StreamZipArchiveCompletion) {
        // 기본 파일 길이를 0으로 리셋
        self.fileLength = 0
        // 파일 길이를 구해온다
        self.delegate?.getFileLength(at: url) { [weak self] (fileLength, error) in
            guard let strongSelf = self else {
                return completion(0, nil, error)
            }
            // 에러 발생시 종료 처리
            if let error = error {
                return completion(0, nil, error)
            }
            
            strongSelf.fileLength = fileLength
            
            // 파일 길이가 0인 경우 종료 처리
            guard strongSelf.fileLength > 0 else {
                return completion(0, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            
        }
    }
    
    /**
     Central Directory 정보를 찾는 메쏘드
     - Parameters:
        - url: `URL`
        - completion: `StreamZipArchiveCompletion`
     */
    func findCentralDirectory(_ url: URL, completion: StreamZipArchiveCompletion) {
        // 파일 길이가 0인 경우 종료 처리
        guard self.fileLength > 0 else {
            print("StreamZipArchive>findCentralDirectory(_:completion:): file length가 0")
            return completion(0, nil, StreamZip.Error.contentsIsEmpty)
        }
        guard let delegate = self.delegate else {
            print("StreamZipArchive>findCentralDirectory(_:completion:): delegate가 nil")
            return completion(0, nil, StreamZip.Error.contentsIsEmpty)
        }
        
        let range = self.fileLength - 4096 ... self.fileLength - 1
        // 해당 범위만큼 데이터를 전송받는다
        delegate.request(at: url, range: range) { [weak self] (data, length, error) in
            guard let strongSelf = self else {
                print("StreamZipArchive>findCentralDirectory(_:completion:): self가 nil!")
                return completion(0, nil, error)
            }
            if let error = error {
                print("StreamZipArchive>findCentralDirectory(_:completion:): 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(0, nil, error)
            }
            guard let data = data else {
                print("StreamZipArchive>findCentralDirectory(_:completion:): 데이터 길이가 0")
                return completion(0, nil, StreamZip.Error.contentsIsEmpty)
            }
            
            // https://stackoverflow.com/questions/31821709/nsdata-to-uint8-in-swift
             var byteData = [UInt8](repeating:0, count: data.count)
             data.copyBytes(to: &byteData, count: data.count)
            
            // https://stackoverflow.com/questions/50285026/swift-convert-data-to-unsafemutablepointerint8
            // https://stackoverflow.com/questions/60869370/unsafemutablepointer-warning-with-swift-5
            // var cptr = UnsafeMutablePointer<UInt8>.allocate(capacity: byteData.count)
            // cptr.initialize(from: &byteData, count: byteData.count)

            // https://stackoverflow.com/questions/39737082/find-if-sequence-of-elements-exists-in-array
            
            var centralDirectorylocation = NSNotFound
            for index in 0 ..< byteData.count - 4  {
                if EndOfCentralDirectorySignature == [byteData[index], byteData[index + 1], byteData[index + 2], byteData[index + 3],] {
                    print("StreamZipArchive>findCentralDirectory(_:completion:): End of Central Directory = \(index)")
                    centralDirectorylocation = index
                    break
                }
            }
        }
    }
}

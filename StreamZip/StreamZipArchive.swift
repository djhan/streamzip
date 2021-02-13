//
//  StreamZipArchive.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation
import Cocoa

import zlib


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
    func request(at url: URL, range: Range<UInt>, completion: StreamZipRequestCompletion)
}

/// ZIP Stream Size
private let ZIP_STREAM_SIZE: Int32 = Int32(MemoryLayout<z_stream>.size)

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
typealias StreamZipArchiveCompletion = (_ fileLength: UInt, _ entries: [StreamZipEntry]?, _ error: Error?) -> Void
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
    /**
     Stream Zip Entry 배열
     */
    lazy var entries = [StreamZipEntry]()

    // MARK: - Initialization

    
    // MARK: - Methods
    
    /**
     특정 URL의 zip 파일에 접근, Entries 배열 생성
     - Parameters:
        - url: `URL`
        - encoding: `String.Encoding` 형으로 파일명 인코딩 지정
        - completion: `StreamZipArchiveCompletion` 완료 핸들러
     */
    func fetchArchive(_ url: URL, encoding: String.Encoding, completion: StreamZipArchiveCompletion) {
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
            
            // Central Directory 정보를 찾고 entry 배열 생성
            strongSelf.makeEntries(url, encoding: encoding, completion: completion)
        }
    }
    
    /**
     Central Directory 정보를 찾아 Entry 배열을 생성하는 내부 메쏘드
     - Parameters:
        - url: `URL`
        - encoding: `String.Encoding`
        - completion: `StreamZipArchiveCompletion`
     */
    private func makeEntries(_ url: URL, encoding: String.Encoding, completion: StreamZipArchiveCompletion) {
        // 파일 길이가 0인 경우 종료 처리
        guard self.fileLength > 0 else {
            print("StreamZipArchive>makeEntries(_:completion:): file length가 0")
            return completion(0, nil, StreamZip.Error.contentsIsEmpty)
        }
        guard let delegate = self.delegate else {
            print("StreamZipArchive>makeEntries(_:completion:): delegate가 nil")
            return completion(0, nil, StreamZip.Error.contentsIsEmpty)
        }
        
        // 마지막 지점에서 -4096 바이트부터 마지막 지점까지 범위 지정
        let range = self.fileLength - 4096 ..< self.fileLength
        // 해당 범위만큼 데이터를 전송받는다
        delegate.request(at: url, range: range) { [weak self] (data, length, error) in
            guard let strongSelf = self,
                  let delegate = strongSelf.delegate else {
                print("StreamZipArchive>makeEntries(_:completion:): self가 nil!")
                return completion(0, nil, error)
            }
            if let error = error {
                print("StreamZipArchive>makeEntries(_:completion:): 최초 마지막 4096 바이트 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(0, nil, error)
            }
            guard let data = data else {
                print("StreamZipArchive>makeEntries(_:completion:): 에러가 없는데 데이터 크기가 0. End of Central Directory가 없는 것일 수 있음")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // End of Central Directory 정보 레코드를 가져온다
            guard let zipEndRecord = ZipEndRecord.make(from: data, encoding: encoding) else {
                print("StreamZipArchive>makeEntries(_:completion:): end of central directory 구조체 초기화 실패!")
                return completion(0, nil, StreamZip.Error.endOfCentralDirectoryIsFailed)
            }
            
            // Central Directory 시작 offset과 size을 가져온다
            let offsetOfCentralDirectory = UInt(zipEndRecord.offsetOfStartOfCentralDirectory)
            let sizeOfCentralDirectory = UInt(zipEndRecord.sizeOfCentralDirectory)
            let centralDirectoryRange = offsetOfCentralDirectory ..< offsetOfCentralDirectory + sizeOfCentralDirectory
            
            // Central Directory data 를 가져온다
            delegate.request(at: url, range: centralDirectoryRange) { [weak self] (data, length, error) in
                guard let strongSelf = self else {
                    print("StreamZipArchive>makeEntries(_:completion:): self가 nil!")
                    return completion(0, nil, error)
                }
                if let error = error {
                    print("StreamZipArchive>makeEntries(_:completion:): central directory data 전송중 에러 발생 = \(error.localizedDescription)")
                    return completion(0, nil, error)
                }
                guard let data = data else {
                    print("StreamZipArchive>makeEntries(_:completion:): 에러가 없는데 central directory data 크기가 0")
                    return completion(0, nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                guard let entries = StreamZipEntry.makeEntries(url, from: data, encoding: encoding) else {
                    print("StreamZipArchive>makeEntries(_:completion:): Stream Zip Entries 생성에 실패")
                    return completion(0, nil, StreamZip.Error.centralDirectoryIsFailed)
                }
                
                // self.entries 프로퍼티에 생성된 entries를 대입
                strongSelf.entries = entries
                
                // 완료 처리
                completion(strongSelf.fileLength, strongSelf.entries, nil)
            }
        }
    }
    
    /**
     특정 Entry의 파일 다운로드
     - 다운로드후 압축 해제된 데이터는 해당 entry의 data 프로퍼티에 격납된다
     */
    func fetchFile(_ entry: StreamZipEntry, encoding: String.Encoding, completion: StreamZipFileCompletion) {
        
        // 이미 data가 있는 경우 nil 처리
        entry.data = nil
    
        guard let delegate = self.delegate else {
            print("StreamZipArchive>fetchFile(_:completion:): delegate가 nil")
            return completion(entry, StreamZip.Error.contentsIsEmpty)
        }

        // 16 바이트를 추가로 다운로드 받는다
        // Central Directory / FileEntry Header 가 포함됐을 수도 있기 때문이다
        // 길이 = zip file header (32바이트) + 압축되어 있는 크기 + 파일명 길이 + extraFieldLength + 추가 16 바이트
        let length = UInt(MemoryLayout<ZipFileHeader>.size + entry.sizeCompressed + entry.filenameLength + entry.extraFieldLength + 16)
        // 추가 16바이트를 더한 값이 전체 파일 길이를 넘어서지 않도록 조절한다
        let maxLength = length > self.fileLength ? self.fileLength : length
        // 다운로드 범위를 구한다
        let range = UInt(entry.offset) ..< maxLength
        // 해당 범위의 데이터를 받아온다
        delegate.request(at: entry.url, range: range) { (data, length, error) in
            if let error = error {
                print("StreamZipArchive>fetchFile(_:completion:): 데이터 전송중 에러 발생 = \(error.localizedDescription)")
                return completion(entry, error)
            }
            guard let data = data else {
                print("StreamZipArchive>fetchFile(_:completion:): 에러가 없는데 데이터 크기가 0")
                return completion(entry, StreamZip.Error.contentsIsEmpty)
            }

            // Local Zip File Header 구조체 생성
            guard let zipFileHeader = ZipFileHeader.make(from: data, encoding: encoding) else {
                print("StreamZipArchive>fetchFile(_:completion:): local file hedaer를 찾지 못함")
                return completion(entry, StreamZip.Error.localFileHeaderIsFailed)
            }
            
            let offset = zipFileHeader.length + Int(zipFileHeader.fileNameLength + zipFileHeader.extraFieldLength)
            
            switch entry.method {
            // Defalte 방식인 경우
            case Z_DEFLATED:
                do {
                    // 성공 처리
                    let decompressData = try data.unzip(offset:offset, compressedSize: entry.sizeCompressed, crc32: entry.crc32)
                    entry.data = decompressData
                    return completion(entry, nil)
                }
                catch {
                    print("StreamZipArchive>fetchFile(_:completion:): 해제 도중 에러 발생 = \(error.localizedDescription)")
                    return completion(entry, error)
                }
                
            // 비압축시
            case 0:
                entry.data = data[offset ..< offset + entry.sizeUncompressed]
                
            // 그 외의 경우
            default:
                print("StreamZipArchive>fetchFile(_:completion:): 미지원 압축 해제 방식. 데이터 해제 불가")
                return completion(entry, StreamZip.Error.unsupportedCompressMethod)
            }
        }
    }
}

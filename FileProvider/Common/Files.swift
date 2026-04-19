//
//  Files.swift
//  EdgeView
//
//  Created by DJ.HAN on 4/18/26.
//  Copyright © 2026 DJ.HAN. All rights reserved.
//

import Foundation

// MARK: - Files Enumeration -
/// 파일 접근 열거형
public enum Files: Sendable {
    
    // MARK: - Cateogry
    /// 종류
    public enum Category {
        /// 이미지
        case image
        /// PDF
        case pdf
        /// 압축 파일
        case archive
        /// 폴더
        case directory
        /// 파일
        case file
        /// 알 수 없는 경우
        case unknown
    }
    
    // MARK: - Conflict
    /// 충돌 발생 시 해결 방안
    /// - 복사 또는 이동 시 같은 파일명의 파일이 있는 경우, 해결 방안
    @frozen public enum Conflict: Sendable {
        /// 건너뛰기
        /// - 기존 파일이나 폴더를 유지한 채 건너뛴다
        case skip
        /// 덮어쓰기
        /// - 기존 파일이나 폴더를 제거
        case overwrite
        /// 병합하기
        /// - 기존 폴더를 유지한다. 다만 폴더 내부에 동일한 파일이 있으면 덮어쓴다.
        case merge

        /// 중지 처리
        case abort
    }
    
    // MARK: - Error
    public enum Error: LocalizedError,
                       CustomStringConvertible {
        
        /// 접근할 서버 정보가 없음
        case noServer
        /// 사용자 이름이 없음
        case noUsername
        /// 비밀번호가 없음
        case noPassword
        /// 정보 부족 또는 로그인 윈도우를 표시 가능한 뷰 컨트롤러가 없음 에러
        case insufficientInformation
        /// 키 접근 불가능 에러
        case cannotAccessToKey
        /// 인증 실패 에러
        case authenticationFailed
        /// 토큰 가져오기 실패 에러
        case tokenFailed
        /// 키체인에서 토큰을 찾을 수 없음
        case keychainFailed

        /// 알 수 없는 키 알고리즘
        case unknownKeyAlgorithm
        /// Private Key 파싱에 실패
        case privateKeyParseFailed
        
        /// 수신 실패 에러
        case receiveFailed
        /// 송신 실패 에러
        case sendFailed
        
        /// 접근 권한이 없음
        case accessDenied
        /// 잘못된 URL
        case invalidURL
        /// drive 미지정 - SMB
        case noDrive
        /// 잘못된 작업 지정
        case accessWrongType
        /// 디렉토리 접근 실패
        case accessDirectoryFailed
        /// 로컬/서버 파일을 여는데 실패
        case openFileFailed
        /// 파일 크기가 0
        case zeroFileSize
        /// 파일 크기 불명
        case unknownFileSize

        /// 알 수 없는 이유로 읽기 실패
        case readFailedByUnknown
        /// 파일 불완전 읽기로 실패
        case readFailedByIncomplete
        /// offset / length 를 잘못 지정
        case readFailedByWrongSize
        /// 너무 작은 파일 크기
        case tooSmallSize
        /// 파일 로컬 저장에 실패
        case saveToLocalFailed

        /// 알 수 없는 이유로 파일/폴더 제거 실패
        case removeFailedByUnknown
        
        /// 알 수 없는 이유로 파일/폴더 이동 실패
        case moveFailedByUnknown
        /// 동일 위치로 이동 불가(동일 파일명으로 변경 불가)
        case moveToSamePathFailed
        
        /// 파일 업로드에 실패
        case uploadFileFailed
        /// 업로드 제한 한도 초과
        case uploadFileOverMaxSize
        /// 디렉토리 생성에 실패
        case makeDirectoryFailed
        
        /// 빈 디렉토리
        case emptyDirectory
        /// 파일/폴더가 존재하지 않음
        case notExist
        /// 폴더가 아님
        case notFolder
        /// 이미지가 아님
        case notImage
        /// 같은 이름의 파일/폴더가 존재함
        case existSameName
        /// 덮어쓰기 불가
        case disallowOverwrite

        /// URL 캐쉬 접근 불가
        case accessToURLCacheFailed
        
        /// 접속 불가
        case connectToServerFailed
        
        /// Request 생성 실패
        case makeRequestFailed
        /// Request 찾기 에러
        case findRequestFailed
        /// Response 에러
        /// - Response 취득 실패
        case responseFailed
        /// 캐쉬 갱신 필요
        case updateURLCacheIsNeeded

        /// 썸네일 생성 실패
        case makeThumbnailFailed
        /// 크기 초과로 썸네일 생성 불가
        case makeThumbnailDisallowedBySize

        /// FileItem 생성 실패
        case makeFileItemFailed
        
        /// CGSize 로 폭/높이를 구할 수 있는 이미지 또는 PDF가 아님
        case cannotGetWidthAndHeight

        /// 사용자 중지
        case abort
        
        /// 알 수 없는 에러
        case unknown
        
        /// FTPKit 의 에러 코드 변환
        public static func convertFromFTPKitError(_ error: NSError) -> Files.Error {
            switch error.code {
            case 10: return .accessWrongType
            case 11: return .openFileFailed
            case 12: return .zeroFileSize
            case 20: return .readFailedByUnknown
            case 21: return .readFailedByIncomplete
            case 22: return .saveToLocalFailed
            case 23: return .readFailedByWrongSize
            case 30: return .uploadFileFailed
            case 40: return .emptyDirectory
            case 98: return .connectToServerFailed
            case 99: return .abort
            default: return .unknown
            }
        }
        
        public var description: String {
            switch self {
                /// 접근할 서버 정보가 없음
            case .noServer: return "No server information.".localized()
                /// 사용자 이름이 없음
            case .noUsername: return "No username.".localized()
                /// 비밀번호가 없음
            case .noPassword: return "No password.".localized()
                /// 정보 부족 또는 로그인 윈도우를 표시 가능한 뷰 컨트롤러가 없음 에러
            case .insufficientInformation: return "Insufficient information.".localized()
                /// 키 접근 불가능 에러
            case .cannotAccessToKey: return "Can't access the key.".localized()
                /// 인증 실패 에러
            case .authenticationFailed: return "Failed to authenticate.".localized()
                /// 토큰 가져오기 실패 에러
            case .tokenFailed: return "Can't get token.".localized()
                /// 키체인에서 토큰을 찾을 수 없음
            case .keychainFailed: return "Can't find token in keychain.".localized()
                
                /// 알 수 없는 키 알고리즘
            case .unknownKeyAlgorithm: return "Unknown key encryption algorithm.".localized()
                /// Private Key 파싱에 실패
            case .privateKeyParseFailed: return "Failed to parse private key.".localized()
                
                /// 수신 실패 에러
            case .receiveFailed: return "Failure to receive.".localized()
                /// 송신 실패 에러
            case .sendFailed: return "Failure to send.".localized()

                /// 접근 권한이 없음
            case .accessDenied: return "Access denied.".localized()
                /// 잘못된 URL
            case .invalidURL: return "Invalid URL.".localized()
                /// drive 미지정 - SMB
            case .noDrive: return "No drive was specified.".localized()
                /// 잘못된 작업 지정
            case .accessWrongType: return "Access to wrong work type.".localized()
                /// 디렉토리 접근 실패
            case .accessDirectoryFailed: return "Failed to access directory.".localized()
                /// 로컬/서버 파일을 여는데 실패
            case .openFileFailed: return "Failed to open file.".localized()
                /// 파일 크기가 0
            case .zeroFileSize: return "File size is 0.".localized()
                /// 파일 크기 불명
            case .unknownFileSize: return "File size is unknown.".localized()
                
                /// 알 수 없는 이유로 읽기 실패
            case .readFailedByUnknown: return "Failed to read due to unknown reason.".localized()
                /// 파일 불완전 읽기로 실패
            case .readFailedByIncomplete: return "Failed to read due to incomplete data.".localized()
                /// offset / length 를 잘못 지정
            case .readFailedByWrongSize: return "Failure to read due to wrong size.".localized()
                /// 너무 작은 크기
            case .tooSmallSize: return "Too small size to read.".localized()
                /// 파일 로컬 저장에 실패
            case .saveToLocalFailed: return "Failed to save to local Path.".localized()

                /// 알 수 없는 이유로 파일/폴더 제거 실패
            case .removeFailedByUnknown: return "Failed to remove due to unknown reason.".localized()
                
                /// 알 수 없는 이유로 파일/폴더 이동 실패
            case .moveFailedByUnknown: return "Failed to move due to unknown reason.".localized()
                /// 동일 위치로 이동 불가(동일 파일명으로 변경 불가)
            case .moveToSamePathFailed: return "Can't move to the same Path.".localized()
                
                /// 파일 업로드에 실패
            case .uploadFileFailed: return "Failed to upload file.".localized()
                /// 업로드 제한 한도 초과
            case .uploadFileOverMaxSize: return "Can't upload file over max size.".localized()
                /// 디렉토리 생성에 실패
            case .makeDirectoryFailed: return "Failed to make directory.".localized()
                
                /// 빈 디렉토리
            case .emptyDirectory: return "Empty directory.".localized()
                /// 파일/폴더가 존재하지 않음
            case .notExist: return "File or folder does not exist.".localized()
                /// 폴더가 아님
            case .notFolder: return "This is not a folder.".localized()
                /// 이미지가 아님
            case .notImage: return "This is not an image file.".localized()
                /// 같은 이름의 파일/폴더가 존재함
            case .existSameName: return "A file or folder with the same name already exists.".localized()
                /// 덮어쓰기 불가
            case .disallowOverwrite: return "Disallow to overwrite.".localized()

                /// URL 캐쉬 접근 불가
            case .accessToURLCacheFailed: return "Can't access URL cache.".localized()
                
                /// 접속 불가
            case .connectToServerFailed: return "Can't connect to server.".localized()
                
                /// Request 생성 에러
            case .makeRequestFailed: return "Can't create URL request.".localized()
                /// Request 찾기 에러
            case .findRequestFailed: return "Can't find URL request.".localized()
                /// Response 에러
            case .responseFailed: return "Can't get URL response.".localized()
                /// 캐쉬 갱신 필요
            case .updateURLCacheIsNeeded: return "Needs to update URL cache.".localized()
                
                /// 썸네일 생성 실패
            case .makeThumbnailFailed: return "Failed to create thumbnail.".localized()
                /// 크기 초과로 썸네일 생성 불가
            case .makeThumbnailDisallowedBySize: return "Can't create thumbnail because of its size.".localized()

                /// FileItem 생성 실패
            case .makeFileItemFailed: return "Failed to create file item.".localized()
                
                /// CGSize 로 폭/높이를 구할 수 있는 이미지 또는 PDF가 아님
            case .cannotGetWidthAndHeight: return "Can't get width and height, because this is not an image or PDF file.".localized()

                /// 사용자 중지
            case .abort: return "User aborted.".localized()
                /// 알 수 없는 에러
            case .unknown: return "An unknown error occurred.".localized()
            }
        }

        public var errorDescription: String? {
            return description
        }
    }
}

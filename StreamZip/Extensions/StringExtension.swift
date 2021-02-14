//
//  StringExtension.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/14.
//

import Foundation

/**
 String 확장
 */
extension String {
    /**
     양측단의 slash(/)가 제거된 String 반환 메쏘드
     */
    func trimmedSlash() -> String {
        // 길이가 1을 초과하지 않는 경우 중지
        guard self.count > 1 else {
            return self
        }
        return self.trimmingCharacters(in: ["/"])
    }
}

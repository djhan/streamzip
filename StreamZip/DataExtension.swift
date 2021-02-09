//
//  DataExtension.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/09.
//

import Foundation
import Cocoa

// MARK: - Extension for DATA -
public extension Data {
    
    /**
     특정 offset에서 일정 length의 데이터를 FixedWidthInteger 값으로 반환
     - Parameters:
        - offset: `Int` 형으로 시작지점 지정
        - length: `Int` 형으로 길이 지정
    - Returns: `UInt32`
     */
    func getValue<T: FixedWidthInteger>(from offset: Int, length: Int) -> T {
        let data = self[offset ..<  offset + length]
        let value = data.reversed().reduce(0) { value, byte in
            return value << 8 | UInt32(byte)
        }
        return T(value)
    }
}

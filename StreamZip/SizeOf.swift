//
//  SizeOf.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/10.
//

import Foundation

/**
 없어진 C타입의 sizeof 메쏘드를 구현
 */

/**
 특정 정수의 사이즈 반환
 */
public func sizeof<T: FixedWidthInteger>(_ int: T) -> Int {
    return int.bitWidth/UInt8.bitWidth
}
/**
 특정 정수형의 사이즈 반환
 */
public func sizeof<T: FixedWidthInteger>(_ intType: T.Type) -> Int {
    return intType.bitWidth/UInt8.bitWidth
}

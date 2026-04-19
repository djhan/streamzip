//
//  DataTransformExtension.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/09.
//

// MARK: - Depreacted -
/// # Important
/// - 포인터를 사용, 데이터 메모리에서 직접 값을 가져오도록 변경한다.

import Foundation

import CommonLibrary

// MARK: - Enumeration of Big/Little Endian -
public enum Endian {
    case big
    case little
}

// MARK: - Protocol for Integer Transform -
/// 정수 변환 프로토콜
/// - [원문 링크](https://forums.swift.org/t/convert-uint8-to-int/30117/19)
/// - Data 또는 특정 정수 배열을 Little / Big Endian에 따라 특정 정수형으로 변환
/// - Important: Generic으로 정수형을 추정하므로, 사용시에는 대입할 변수/상수에 정수형을 미리 선언해서 사용해야 한다
/// ````
/// let testOffset: UInt64 = data.toInteger(endian: .little)
/// ````
public protocol IntegerTransform: Sequence where Element: FixedWidthInteger {
    func toInteger<I: FixedWidthInteger>(endian: Endian) -> I
}

public extension IntegerTransform {
    /// 특정 정수형으로 변환해 반환
    /// - Parameter endian: 리틀/빅 Endian 지정
    /// - Returns: `FixedWidthInteger` 정수형으로 반환
    func toInteger<I: FixedWidthInteger>(endian: Endian) -> I {
        let f = { (accum: I, next: Element) in accum &<< next.bitWidth | I(next) }
        return endian == .big ? reduce(0, f) : reversed().reduce(0, f)
    }
}

/// Data를 IntegerTransform 프로토콜로 확장
extension Data: IntegerTransform {}
/// FixedWidthInteger Array를 IntegerTransform 프로토콜로 확장
extension Array: IntegerTransform where Element: FixedWidthInteger {}


//
//  Read.swift
//  EdgeStreamZip
//
//  Created by DJ.HAN on 2/1/26.
//

import Foundation

/// 메모리 버퍼에서 일정 간격을 두고 일정한 타입의 길이만큼 데이터를 읽는 메쏘드
/// - Important: 포인터 메모리에 접근, 반복적으로 데이터를 읽어들이는 용도로 사용한다.
func read<T: FixedWidthInteger>(_ type: T.Type, from buffer: UnsafeRawBufferPointer, offset: inout Int) -> T? {
    guard buffer.count >= offset + MemoryLayout<T>.size else { return nil }
    let value = buffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: T.self).pointee
    offset += MemoryLayout<T>.size
    return T(littleEndian: value)
}

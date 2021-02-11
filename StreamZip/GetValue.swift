//
//  GetValue.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/11.
//

import Foundation


/**
 data로부터 특정 프로퍼티 값 반환
 - offset를 inout 패러미터로 지정
 `FixedWidthInteger` 타입만 지정 가능
 - Parameters:
    - data: `Data`
    - offset: inout로 시작 지점 지정. 프로퍼티의 size를 추가해서 반환한다
 - Returns: `FixedWidthInteger` 타입 프로퍼티 반환. 실패시 nil 반환
 */
@discardableResult
internal func getValue<T: FixedWidthInteger>(from data: Data, offset: inout Int) -> T? {
    // 가져올 길이를 property의 타입 기준으로 구한다
    let length = T.bitWidth/UInt8.bitWidth
    guard offset + length <= data.count else { return nil }
    let property: T = data.getValue(from: offset, length: length, endian: .little)
    // offset에 length를 추가한다
    offset += length
    return property
}
/**
 data로부터 데이터를 잘라내서 반환
 - offset를 inout 패러미터로 지정
 - Parameters:
    - data: `Data`
    - offset: inout로 시작 지점 지정. 성공시 가져온 length 만큼 추가된다
    - length: 특정 길이만큼 데이터를 가져온다
 - Returns: Data 반환. 실패시 nil 반환
 */
@discardableResult
internal func getData(from data: Data, offset: inout Int, length: Int) -> Data? {
    guard offset + length <= data.count else { return nil }
    let data = data[offset ..< offset + length]
    // offset에 length를 추가한다
    offset += length
    return data
}

/**
 Data 형 Time과 Date 을 Date로 변환해서 반환
 */
internal func getDate(fromTime time: UInt16, fromDate date: UInt16) -> Date? {
    var dateComponents = DateComponents.init()
    dateComponents.calendar = Calendar.current
    dateComponents.second = Int((time & 0x1F) << 1)
    dateComponents.minute = Int((time & 0x7E0) >> 5)
    dateComponents.hour = Int((time & 0xF800) >> 11)
    dateComponents.day = Int(date & 0x1F)
    dateComponents.month = Int((date & 0x1E0) >> 5)
    dateComponents.year = Int(((date & 0xFE00) >> 9) + 1980)
    return dateComponents.date
}

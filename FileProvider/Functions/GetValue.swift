//
//  GetValue.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/11.
//

import Foundation

/// Data 형 Time과 Date 을 Date로 변환해서 반환
internal func date(fromTime time: UInt16, fromDate date: UInt16) -> Date? {
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

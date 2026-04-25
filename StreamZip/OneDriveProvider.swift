//
//  OneDriveProvider.swift
//  StreamZip
//
//  Created by DJ.HAN on 4/25/26.
//

import Foundation

public actor OneDriveProvider {
    
    // MARK: - Properties
    /// 싱글톤 오브젝트
    public static var shared = OneDriveProvider()
        
    /// OneDrive Files Provider
    var onedriveProvider: OneDriveFilesProvider?
}

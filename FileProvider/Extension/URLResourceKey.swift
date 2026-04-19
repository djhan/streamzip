//
//  URLResourceKey.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/19/25.
//

import Foundation

extension URLResourceKey {
    /// returns url of file object.
    public static let fileURLKey = URLResourceKey(rawValue: "NSURLFileURLKey")
    /// returns modification date of file in server
    public static let serverDateKey = URLResourceKey(rawValue: "NSURLServerDateKey")
    /// returns HTTP ETag string of remote resource
    public static let entryTagKey = URLResourceKey(rawValue: "NSURLEntryTagKey")
    /// returns MIME type of file, if returned by server
    public static let mimeTypeKey = URLResourceKey(rawValue: "NSURLMIMETypeIdentifierKey")
    /// returns either file is encrypted or not
    public static let isEncryptedKey = URLResourceKey(rawValue: "NSURLIsEncryptedKey")
    /// count of items in directory
    public static let childrensCount = URLResourceKey(rawValue: "MFPURLChildrensCount")
}

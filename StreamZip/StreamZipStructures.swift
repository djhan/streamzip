//
//  StreamZipStructures.swift
//  StreamZip
//
//  Created by DJ.HAN on 2021/02/08.
//

import Foundation

/// Zip End Record 구조체
struct zip_end_record {
    var endOfCentralDirectorySignature: UInt32
    var numberOfThisDisk: UInt16
    var diskWhereCentralDirectoryStarts: UInt16
    var numberOfCentralDirectoryRecordsOnThisDisk: UInt16
    var totalNumberOfCentralDirectoryRecords: UInt16
    var sizeOfCentralDirectory: UInt32
    var offsetOfStartOfCentralDirectory: UInt32
    var ZIPfileCommentLength: UInt16
}

/// Zip Directory Record 구조체
struct zip_dir_record {
    var centralDirectoryFileHeaderSignature: UInt32
    var versionMadeBy: UInt16
    var versionNeededToExtract: UInt16
    var generalPurposeBitFlag: UInt16
    var compressionMethod: UInt16
    var fileLastModificationTime: UInt16
    var fileLastModificationDate: UInt16
    var CRC32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var fileNameLength: UInt16
    var extraFieldLength: UInt16
    var fileCommentLength: UInt16
    var diskNumberWhereFileStarts: UInt16
    var internalFileAttributes: UInt16
    var externalFileAttributes: UInt32
    var relativeOffsetOfLocalFileHeader: UInt32
}

/// Zip File Header 구조체
struct zip_file_header {
    var localFileHeaderSignature: UInt32
    var versionNeededToExtract: UInt16
    var generalPurposeBitFlag: UInt16
    var compressionMethod: UInt16
    var fileLastModificationTime: UInt16
    var fileLastModificationDate: UInt16
    var CRC32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var fileNameLength: UInt16
    var extraFieldLength: UInt16
}

//
//  StreamZipTests.swift
//  StreamZipTests
//
//  Created by DJ.HAN on 2021/02/08.
//

import XCTest
@testable import StreamZip


class StreamZipTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    func testSizeOf() {
        print("size of header = \(MemoryLayout<ZipFileHeader>.size)")
    }

    func testLocal() {
        let url = URL.init(fileURLWithPath: "/Users/djhan/Desktop/exr.zip")
        let archiver = StreamZipArchiver.init(fileURL: url)

        let expt = expectation(description: "Waiting done parsing...")
        let progress = archiver?.makeEntriesFromLocal(completion: { fileLength, entries, error in
            if let error = error {
                print("error = \(error.localizedDescription)")
            }
            guard let entries = entries else {
                print("문제 발생!")
                return
            }
            for entry in entries {
                print("entry = \(entry.filePath)")
            }
            // 종료 처리
            expt.fulfill()
        })
        waitForExpectations(timeout: 3.0, handler: nil)
    }
}

//
//  URLError.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/26/25.
//

import Foundation

extension URLError {
    init(_ code: URLError.Code, url: URL?) {
        if let url = url {
            let userInfo: [String: Any] = [NSURLErrorKey: url,
                                           NSURLErrorFailingURLErrorKey: url]
            self.init(code, userInfo: userInfo)
        } else {
            self.init(code)
        }
    }
}

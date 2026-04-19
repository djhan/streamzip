//
//  CharacterSetExtension.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

internal extension CharacterSet {
    static let filePathAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":"))
}

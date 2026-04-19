//
//  FIleOperationType.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

// MARK: - File Opeation Type Enumeration -
public enum FileOperationType: CustomStringConvertible {
    /// Creating a file or directory in path.
    case create (path: String)
    /// Copying a file or directory from source to destination.
    case copy   (source: String, destination: String)
    /// Moving a file or directory from source to destination.
    case move   (source: String, destination: String)
    /// Modifying data of a file o in path by writing new data.
    case modify (path: String)
    /// Deleting file or directory in path.
    case remove (path: String)
    /// Creating a symbolic link or alias to target.
    case link   (link: String, target: String)
    /// Fetching data in file located in path.
    case fetch  (path: String)
    
    public var description: String {
        switch self {
        case .create: return "Create"
        case .copy: return "Copy"
        case .move: return "Move"
        case .modify: return "Modify"
        case .remove: return "Remove"
        case .link: return "Link"
        case .fetch: return "Fetch"
        }
    }
    
    /// present participle of action, like `Copying`.
    public var actionDescription: String {
        return description.trimmingCharacters(in: CharacterSet(charactersIn: "e")) + "ing"
    }
    
    /// Path of subjecting file.
    public var source: String {
        let reflect = Mirror(reflecting: self).children.first!.value
        let mirror = Mirror(reflecting: reflect)
        return reflect as? String ?? mirror.children.first?.value as! String
    }
    
    /// Path of subjecting file.
    public var path: String? {
        return source
    }
    
    /// Path of destination file.
    public var destination: String? {
        guard let reflect = Mirror(reflecting: self).children.first?.value else { return nil }
        let mirror = Mirror(reflecting: reflect)
        return mirror.children.dropFirst().first?.value as? String
    }
    
    /// JSON 스트링 반환
    internal var json: String? {
        var dictionary: [String: Any] = ["type": self.description]
        dictionary["source"] = source
        dictionary["dest"] = destination
        return String(jsonDictionary: dictionary)
    }

    // MARK: - Initializaiton
    /// JSON 딕셔너리로 초기화
    init? (json: [String: Any]) {
        guard let type = json["type"] as? String, let source = json["source"] as? String else {
            return nil
        }
        let dest = json["dest"] as? String
        switch type {
        case "Fetch":
            self = .fetch(path: source)
        case "Create":
            self = .create(path: source)
        case "Modify":
            self = .modify(path: source)
        case "Remove":
            self = .remove(path: source)
        case "Copy":
            guard let dest = dest else { return nil }
            self = .copy(source: source, destination: dest)
        case "Move":
            guard let dest = dest else { return nil }
            self = .move(source: source, destination: dest)
        case "Link":
            guard let dest = dest else { return nil }
            self = .link(link: source, target: dest)
        default:
            return nil
        }
    }
}

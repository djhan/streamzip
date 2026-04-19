//
//  AEXMLElement.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

// MARK: - AEXML Element Class -

/**
    This is base class for holding XML structure.

    You can access its structure by using subscript like this: `element["foo"]["bar"]` which would
    return `<bar></bar>` element from `<element><foo><bar></bar></foo></element>` XML as an `AEXMLElement` object.
*/
open class AEXMLElement {
    
    // MARK: - Properties
    
    /// Every `AEXMLElement` should have its parent element instead of `AEXMLDocument` which parent is `nil`.
    internal weak var parent: AEXMLElement?
    
    /// Child XML elements.
    internal var children = [AEXMLElement]()
    
    /// XML Element name.
    open var name: String
    
    /// XML Element value.
    open var value: String?
    
    /// XML Element attributes.
    open var attributes: [String: String]
    
    /// Error value (`nil` if there is no error).
    open var error: AEXMLError?
    
    /// String representation of `value` property (if `value` is `nil` this is empty String).
    open var string: String { value ?? "" }
    
    /// Boolean representation of `value` property (if `value` is "true" or 1 this is `true`, otherwise `false`).
    open var bool: Bool {
        let lowercased = string.lowercased()
        return lowercased == "true" || lowercased == "1" || Int(string) == 1
    }
    
    /// Integer representation of `value` property (this is **0** if `value` can't be represented as Integer).
    open var int: Int { Int(string) ?? 0 }
    
    /// Double representation of `value` property (this is **0.00** if `value` can't be represented as Double).
    open var double: Double { Double(string) ?? 0.00 }
    
    // MARK: - Lifecycle
    
    /**
        Designated initializer - all parameters are optional.
    
        - parameter name: XML element name.
        - parameter value: XML element value (defaults to `nil`).
        - parameter attributes: XML element attributes (defaults to empty dictionary).
    
        - returns: An initialized `AEXMLElement` object.
    */
    public init(name: String, value: String? = nil, attributes: [String: String] = [:]) {
        self.name = name
        self.value = value
        self.attributes = attributes
    }
    
    // MARK: - XML Read
    
    /// The first element with given name **(Empty element with error if not exists)**.
    open subscript(key: String) -> AEXMLElement {
        if let first = children.first(where: { $0.name == key }) {
            return first
        }
        
        let errorElement = AEXMLElement(name: key)
        errorElement.error = AEXMLError.elementNotFound
        return errorElement
    }
    
    /// Returns all of the elements with equal name as `self` **(nil if not exists)**.
    open var all: [AEXMLElement]? {
        guard let elements = parent?.children.filter({ $0.name == name }), !elements.isEmpty else {
            return nil
        }
        return elements
    }
    
    /// Returns the first element with equal name as `self` **(nil if not exists)**.
    open var first: AEXMLElement? { all?.first }
    
    /// Returns the last element with equal name as `self` **(nil if not exists)**.
    open var last: AEXMLElement? { all?.last }
    
    /// Returns number of all elements with equal name as `self`.
    open var count: Int { all?.count ?? 0 }

    private func filter(withCondition condition: (AEXMLElement) -> Bool) -> [AEXMLElement]? {
        guard let elements = all else { return nil }
        
        let found = elements.filter(condition)
        return found.isEmpty ? nil : found
    }
    
    /**
        Returns all elements with given value.
        
        - parameter value: XML element value.
        
        - returns: Optional Array of found XML elements.
    */
    open func all(withValue value: String) -> [AEXMLElement]? {
        filter { $0.value == value }
    }
    
    /**
        Returns all elements with given attributes.
    
        - parameter attributes: Dictionary of Keys and Values of attributes.
    
        - returns: Optional Array of found XML elements.
    */
    open func all(withAttributes attributes: [String: String]) -> [AEXMLElement]? {
        filter { element in
            attributes.allSatisfy { key, value in
                element.attributes[key] == value
            }
        }
    }
    
    // MARK: - XML Write
    
    /**
        Adds child XML element to `self`.
    
        - parameter child: Child XML element to add.
    
        - returns: Child XML element with `self` as `parent`.
    */
    @discardableResult
    open func addChild(_ child: AEXMLElement) -> AEXMLElement {
        child.parent = self
        children.append(child)
        return child
    }
    
    /**
        Adds child XML element to `self`.
        
        - parameter name: Child XML element name.
        - parameter value: Child XML element value (defaults to `nil`).
        - parameter attributes: Child XML element attributes (defaults to empty dictionary).
        
        - returns: Child XML element with `self` as `parent`.
    */
    @discardableResult
    open func addChild(name: String, value: String? = nil, attributes: [String: String] = [:]) -> AEXMLElement {
        let child = AEXMLElement(name: name, value: value, attributes: attributes)
        return addChild(child)
    }
    
    /// Removes `self` from `parent` XML element.
    open func removeFromParent() {
        parent?.removeChild(self)
    }
    
    private func removeChild(_ child: AEXMLElement) {
        if let childIndex = children.firstIndex(where: { $0 === child }) {
            children.remove(at: childIndex)
        }
    }
    
    private var parentsCount: Int {
        var count = 0
        var element = self
        
        while let parent = element.parent {
            count += 1
            element = parent
        }
        
        return count
    }
    
    private func indent(withDepth depth: Int) -> String {
        String(repeating: "\t", count: max(0, depth))
    }
    
    /// Complete hierarchy of `self` and `children` in **XML** escaped and formatted String
    open var xml: String {
        var xml = ""
        
        // open element
        xml += indent(withDepth: parentsCount - 1)
        xml += "<\(name)"
        
        // insert attributes
        if !attributes.isEmpty {
            for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
                xml += " \(key)=\"\(value.xmlEscaped)\""
            }
        }
        
        if value == nil && children.isEmpty {
            // close element
            xml += " />"
        } else {
            if !children.isEmpty {
                // add children
                xml += ">\n"
                for child in children {
                    xml += "\(child.xml)\n"
                }
                // add indentation
                xml += indent(withDepth: parentsCount - 1)
                xml += "</\(name)>"
            } else {
                // insert string value and close element
                xml += ">\(string.xmlEscaped)</\(name)>"
            }
        }
        
        return xml
    }
    
    /// Same as `xml` but without `\n` and `\t` characters
    open var xmlCompact: String {
        xml.replacingOccurrences(of: "[\n\t]+", with: "", options: .regularExpression)
    }
    
}

// MARK: - String Extension

extension String {
    
    /// String representation of self with XML special characters escaped.
    public var xmlEscaped: String {
        // we need to make sure "&" is escaped first. Not doing this may break escaping the other characters
        var escaped = replacingOccurrences(of: "&", with: "&amp;", options: .literal)
        
        // replace the other four special characters
        let escapeChars = ["<": "&lt;", ">": "&gt;", "'": "&apos;", "\"": "&quot;"]
        for (char, echar) in escapeChars {
            escaped = escaped.replacingOccurrences(of: char, with: echar, options: .literal)
        }
        
        return escaped
    }
}

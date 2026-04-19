//
//  AEXMLDocument.swift
//  EdgeFileProvider
//
//  Created by DJ.HAN on 11/18/25.
//

import Foundation

// MARK: - AEXML Document Options Struct -

/// Options used in `AEXMLDocument`
internal struct AEXMLOptions {
    
    /// Values used in XML Document header
    public struct DocumentHeader {
        /// Version value for XML Document header (defaults to 1.0).
        public var version = 1.0
        
        /// Encoding value for XML Document header (defaults to "utf-8").
        public var encoding = "utf-8"
        
        /// Standalone value for XML Document header (defaults to "no").
        public var standalone = "no"
        
        /// XML Document header
        public var xmlString: String {
            return "<?xml version=\"\(version)\" encoding=\"\(encoding)\" standalone=\"\(standalone)\"?>"
        }
    }
    
    /// Settings used by `Foundation.XMLParser`
    public struct ParserSettings {
        /// Parser reports the namespaces and qualified names of elements. (defaults to `false`)
        public var shouldProcessNamespaces = false
        
        /// Parser reports the prefixes indicating the scope of namespace declarations. (defaults to `false`)
        public var shouldReportNamespacePrefixes = false
        
        /// Parser reports declarations of external entities. (defaults to `false`)
        public var shouldResolveExternalEntities = false
    }
    
    /// Values used in XML Document header (defaults to `DocumentHeader()`)
    public var documentHeader = DocumentHeader()
    
    /// Settings used by `Foundation.XMLParser` (defaults to `ParserSettings()`)
    public var parserSettings = ParserSettings()
    
    /// Designated initializer - Creates and returns default `AEXMLOptions`.
    public init() {}
    
}

// MARK: - AEXML Document Class -
internal class AEXMLDocument: AEXMLElement {
    
    // MARK: - Properties
    
    /// Root (the first child element) element of XML Document **(Empty element with error if not exists)**.
    open var root: AEXMLElement {
        guard let rootElement = children.first else {
            let errorElement = AEXMLElement(name: "Error")
            errorElement.error = AEXMLError.rootElementMissing
            return errorElement
        }
        return rootElement
    }
    
    public let options: AEXMLOptions
    
    // MARK: - Lifecycle
    
    /**
        Designated initializer - Creates and returns new XML Document object.
     
        - parameter root: Root XML element for XML Document (defaults to `nil`).
        - parameter options: Options for XML Document header and parser settings (defaults to `AEXMLOptions()`).
    
        - returns: Initialized XML Document object.
    */
    public init(root: AEXMLElement? = nil, options: AEXMLOptions = AEXMLOptions()) {
        self.options = options
        
        let documentName = String(describing: AEXMLDocument.self)
        super.init(name: documentName)
        
        // document has no parent element
        self.parent = nil
        
        // add root element to document (if any)
        if let rootElement = root {
            _ = addChild(rootElement)
        }
    }
    
    /**
        Convenience initializer - used for parsing XML data (by calling `loadXMLData:` internally).
     
        - parameter xmlData: XML data to parse.
        - parameter options: Options for XML Document header and parser settings (defaults to `AEXMLOptions()`).
    
        - returns: Initialized XML Document object containing parsed data. Throws error if data could not be parsed.
    */
    public convenience init(xml: Data, options: AEXMLOptions = AEXMLOptions()) throws {
        self.init(options: options)
        try loadXML(xml)
    }
    
    /**
        Convenience initializer - used for parsing XML string (by calling `init(xmlData:options:)` internally).

        - parameter xmlString: XML string to parse.
        - parameter encoding: String encoding for creating `Data` from `xmlString` (defaults to `String.Encoding.utf8`)
        - parameter options: Options for XML Document header and parser settings (defaults to `AEXMLOptions()`).

        - returns: Initialized XML Document object containing parsed data. Throws error if data could not be parsed.
    */
    public convenience init(xml: String,
                            encoding: String.Encoding = String.Encoding.utf8,
                            options: AEXMLOptions = AEXMLOptions()) throws {
        guard let data = xml.data(using: encoding) else { throw AEXMLError.parsingFailed }
        try self.init(xml: data, options: options)
    }
    
    // MARK: - Parse XML
    
    /**
        Creates instance of `AEXMLParser` (private class which is simple wrapper around `XMLParser`)
        and starts parsing the given XML data. Throws error if data could not be parsed.
    
        - parameter data: XML which should be parsed.
    */
    open func loadXML(_ data: Data) throws {
        children.removeAll(keepingCapacity: false)
        let xmlParser = AEXMLParser(document: self, data: data)
        try xmlParser.parse()
    }
    
    // MARK: - Override
    
    /// Override of `xml` property of `AEXMLElement` - it just inserts XML Document header at the beginning.
    open override var xml: String {
        var xml =  "\(options.documentHeader.xmlString)\n"
        for child in children {
            xml += child.xml
        }
        return xml
    }
    
}

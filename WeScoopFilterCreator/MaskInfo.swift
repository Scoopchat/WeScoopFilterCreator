//
//  MaskInfo.swift
//  ARMetal
//
//  Created by joshua bauer on 5/17/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation


struct MaskInfo : Decodable {
    
    private static var isDirectory: ObjCBool = true
    private static var maskCacheDirectoryURL : URL?
    
    enum MaskType: String  {
        case filter,scene,face,mask
    }
    
    enum Tier: String  {
        case low, high
    }
    
    enum Status: String  {
        case inactive, active
    }
    
    struct Multipliers : Codable {
        let base : Float?
        let fire : Float?
        let difficulty : Float?
        
        enum CodingKeys: String, CodingKey {
            case base = "base"
            case fire = "fire"
            case difficulty = "difficulty"
        }
        
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            base = try values.decodeIfPresent(Float.self, forKey: .base)
            fire = try values.decodeIfPresent(Float.self, forKey: .fire)
            difficulty = try values.decodeIfPresent(Float.self, forKey: .difficulty)
        }
    }
    
    
    let id : Int
    let updatedAt : Date?
    let createdAt : Date?
    let name : String
    let resourcePath : String
    let iconPath : String
    let imagePath : String?
    let status : Status?
    let type : MaskType?
    let level : Int?
    let price : Int?
    let tier : Tier?
    let featured : Bool?
    let sponsored : Bool?
    let version : Int?
    let position : Int?
    let multipliers : Multipliers?
    var localBasePath: String?
    
    private var _assetFolderName: String?
    
    lazy var assetFolderName: String =  {
        
            if _assetFolderName != nil {
                    return _assetFolderName!
            }
        
            guard let basePath = self.localBasePath else {
                return name + ".scnassets"
            }
            
            let fileManager = FileManager.default
        
            let enumerator: FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: basePath)!
        
            while let element = enumerator.nextObject() as? String, element.hasSuffix(".scnassets") {
                _assetFolderName = element
            }
        
            if _assetFolderName == nil {
                _assetFolderName = name + ".scnassets"
            }
            
            return _assetFolderName!
        
    }()
    
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case updatedAt = "updatedAt"
        case createdAt = "createdAt"
        case name = "name"
        case resourcePath = "resourcePath"
        case iconPath = "iconPath"
        case imagePath = "imagePath"
        case status = "status"
        case type = "type"
        case level = "level"
        case price = "price"
        case tier = "tier"
        case featured = "featured"
        case sponsored = "sponsored"
        case version = "version"
        case position = "position"
        case multipliers
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id)!
        
        
        if let updatedAtMilliseconds = try values.decodeIfPresent(Int.self, forKey: .updatedAt) {
            updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMilliseconds / 1000))
        } else {
            updatedAt = nil
        }
        
        if let createdAtMilliseconds = try values.decodeIfPresent(Int.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMilliseconds / 1000))
        } else {
            createdAt = nil
        }
        
        name = try values.decodeIfPresent(String.self, forKey: .name)!
        resourcePath = try values.decodeIfPresent(String.self, forKey: .resourcePath)!
        iconPath = try values.decodeIfPresent(String.self, forKey: .iconPath)!
        imagePath = try values.decodeIfPresent(String.self, forKey: .imagePath)
 
        if let statusString = try values.decodeIfPresent(String.self, forKey: .status) {
            status = Status(rawValue:statusString)
        } else {
            status = nil
        }
        
        if let typeString = try values.decodeIfPresent(String.self, forKey: .type) {
            type = MaskType(rawValue:typeString)
        } else {
            type = nil
        }
        
        level = try values.decodeIfPresent(Int.self, forKey: .level)
        price = try values.decodeIfPresent(Int.self, forKey: .price)
        
        if let tierString = try values.decodeIfPresent(String.self, forKey: .tier) {
            tier = Tier(rawValue:tierString)
        } else {
            tier = nil
        }
        
        featured = try values.decodeIfPresent(Bool.self, forKey: .featured)
        sponsored = try values.decodeIfPresent(Bool.self, forKey: .sponsored)
        version = try values.decodeIfPresent(Int.self, forKey: .version)
        position = try values.decodeIfPresent(Int.self, forKey: .position)
        multipliers = try Multipliers(from: decoder)
    }
    
    
    // MARK: Helper Methods
    
    static func getMaskCacheDirectoryURL() -> URL {
        
        if let url = maskCacheDirectoryURL {
            return url
        }
        
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        
        let masksURL = cacheURL?.appendingPathComponent(  "masks")
        
        maskCacheDirectoryURL = masksURL
        
        if !FileManager.default.fileExists(atPath: masksURL!.path, isDirectory: &isDirectory) {
            
            do {
                try FileManager.default.createDirectory(at: masksURL!, withIntermediateDirectories: true, attributes: nil)
            } catch  {
                print("Failed to create temp mask directroy")
            }
            
            
        }
        return maskCacheDirectoryURL!
    }
    
    static func synchronizeMaskContent( info: MaskInfo, completionHandler: ( (URL?)  -> Void )? )    {
        
        let fileManager = FileManager.default
        
        let maskBaseURL = getMaskCacheDirectoryURL().appendingPathComponent( info.name )
        
        if fileManager.fileExists(atPath: maskBaseURL.path, isDirectory: &isDirectory) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: maskBaseURL.path)
                if let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date {
                    
                    print("folder created \(modificationDate) updated \(info.updatedAt!)")
                    if modificationDate.compare(info.updatedAt!) == ComparisonResult.orderedDescending {
                        print("current version of \(info.name) is up to date: \(maskBaseURL.path)")
                
                        completionHandler?(maskBaseURL)
                        return
                    }
                }
                
            }
            catch {
                print("Failed to access mask directory attributes")
            }
        }
        
        print("current version of \(info.name) is not up to date")
        
  
       // downloadMaskResources( info: info, completionHandler: completionHandler )
        
        
    }
    
    
}

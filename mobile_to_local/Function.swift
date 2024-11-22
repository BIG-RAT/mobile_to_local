//
//  Function.swift
//  Mobile to Local
//
//  Created by leslie on 11/22/24.
//  Copyright © 2024 jamf. All rights reserved.
//

import Foundation
import OpenDirectory

class Function: NSObject {
    
    static let shared = Function()
    
    func isAdmin(username: String) -> Bool {
        do {
            // Open the local directory
            let session = ODSession.default()
            let node = try ODNode(session: session, name: "/Local/Default")
            
            // Get the admin group record
            let query = try node.record(withRecordType: kODRecordTypeGroups, name: "admin", attributes: nil)
            
            // Get the group members (this resolves nested memberships)
            if let members = try query.values(forAttribute: kODAttributeTypeGroupMembership) as? [String] {
                return members.contains(username)
            }
            
            // Check nested groups (GroupMembers attribute resolves nested entries)
            if let nestedGroups = try query.values(forAttribute: kODAttributeTypeGroupMembers) as? [String] {
                let userRecord = try node.record(withRecordType: kODRecordTypeUsers, name: username, attributes: nil)
                let userUUID = try userRecord.values(forAttribute: kODAttributeTypeGUID) as? [String]
                return userUUID?.contains(where: nestedGroups.contains) ?? false
            }
        } catch {
            print("Error checking admin privileges: \(error)")
        }
        return false
    }

    func isMobile(username: String) -> Bool {
        do {
            // Open the local directory node
            let session = ODSession.default()
            let node = try ODNode(session: session, type: UInt32(kODNodeTypeLocalNodes))
            
            // Get the user record
            let userRecord = try node.record(
                withRecordType: kODRecordTypeUsers,
                name: username,
                attributes: nil
            )
            
            // Check the OriginalNodeName attribute
            if let originalNodeName = try? userRecord.values(forAttribute: "dsAttrTypeStandard:OriginalNodeName") as? [String],
               !originalNodeName.isEmpty {
                print("OriginalNodeName: \(originalNodeName)")
                return true // OriginalNodeName is set, indicating a mobile account
            }
            
            // Check the AuthenticationAuthority attribute for "LocalCachedUser"
            if let authAuthority = try? userRecord.values(forAttribute: kODAttributeTypeAuthenticationAuthority) as? [String] {
                for authority in authAuthority {
                    if authority.contains("LocalCachedUser") {
                        print("AuthenticationAuthority contains LocalCachedUser: \(authority)")
                        return true // Indicates a cached mobile account
                    }
                }
            }
        } catch {
            print("Error checking if user is a mobile AD account: \(error)")
        }
        
        return false
    }

    func adminGroup(username: String, operation: String) -> Bool {
        do {
            // Open the local directory node
            let session = ODSession.default()
            let node = try ODNode(session: session, type: UInt32(kODNodeTypeLocalNodes))
            
            // Fetch the admin group record
            let adminGroupRecord = try node.record(
                withRecordType: kODRecordTypeGroups,
                name: "admin",
                attributes: nil
            )
            
            // Add/remove the user
            if operation == "add" {
                try adminGroupRecord.addValue(username, toAttribute: kODAttributeTypeGroupMembership)
            } else {
                try adminGroupRecord.removeValue(username, fromAttribute: kODAttributeTypeGroupMembership)
            }
            try adminGroupRecord.synchronize()
            
            print("Admin group - successfully \(operation.replacingOccurrences(of: "ove", with: "ov")).ed user \(username).")
            return true
        } catch {
            print("\(operation.localizedCapitalized) operation failed: \(error)")
            return false
        }
    }
    
}

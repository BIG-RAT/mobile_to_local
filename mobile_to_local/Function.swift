//
//  Function.swift
//  Mobile to Local
//
//  Copyright © 2024 jamf. All rights reserved.
//

import Foundation
import OpenDirectory
import SystemConfiguration

class Function: NSObject {
    
    static let shared = Function()
    
    func aaCleanup(username: String) -> [String] {
        var message = [String]()
        
        print("username: \(username)")
        
        do {
            // Connect to the local node
//            guard let session = ODSession.default() else {
//                print("Unable to create ODSession")
////                throw NSError(domain: "OpenDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create ODSession"])
//                return ["Unable to create ODSession"]
//            }
//            print("Created ODSession")
//            
//            let node = try ODNode(session: session, type: UInt32(kODNodeTypeLocalNodes))
//            print("Connected to /Local/Default")
//            
//            // Find the user record
//            let query = try ODQuery(
//                node: node,
//                forRecordTypes: kODRecordTypeUsers,
//                attribute: kODAttributeTypeRecordName,
//                matchType: ODMatchType(kODMatchEqualTo),
//                queryValues: username,
//                returnAttributes: kODAttributeTypeNativeOnly,
//                maximumResults: 1
//            )
//
//            guard let results = try query.resultsAllowingPartial(false) as? [ODRecord], let userRecord = results.first else {
//                print("User not found: \(username).")
////                throw NSError(domain: "OpenDirectory", code: 3, userInfo: [NSLocalizedDescriptionKey: "User not found."])
//                return ["User not found: \(username)"]
//            }
            guard let userRecord = try getUserRecord(username: username) else {
                return ["User not found: \(username)"]
            }
            
            // Fetch the current AuthenticationAuthority attribute
            guard let authAuthorities = try userRecord.values(forAttribute: kODAttributeTypeAuthenticationAuthority) as? [String] else {
                print("AuthenticationAuthority attribute not found")
                return ["AuthenticationAuthority attribute not found"]
//                throw NSError(domain: "OpenDirectory", code: 3, userInfo: [NSLocalizedDescriptionKey: "AuthenticationAuthority attribute not found"])
            }
            print("Current AuthenticationAuthority attribute: \(authAuthorities)")
            
            // Filter out the LocalCachedUser entry
//            var updatedAuthAuthorities = authAuthorities.filter { !$0.contains("LocalCachedUser") }
//            updatedAuthAuthorities = updatedAuthAuthorities.filter { !$0.contains("Kerberosv5") }
            
            // Update the AuthenticationAuthority attribute
            message = ["updating AuthenticationAuthority"]
            for attrib in authAuthorities {
                if attrib.contains("LocalCachedUser") || attrib.contains("Kerberosv5") {
                    print("Try to removed attribute: \(attrib)")
                    try userRecord.removeValue(attrib, fromAttribute: kODAttributeTypeAuthenticationAuthority)
                    print("Removed attribute: \(attrib)")
                }
            }
            guard let newAuthorities = try userRecord.values(forAttribute: kODAttributeTypeAuthenticationAuthority) as? [String] else {
                print("AuthenticationAuthority attribute not found")
                return ["AuthenticationAuthority attribute not found"]
//                throw NSError(domain: "OpenDirectory", code: 3, userInfo: [NSLocalizedDescriptionKey: "AuthenticationAuthority attribute not found"])
            }
            
//            try userRecord.setValue(updatedAuthAuthorities, forAttribute: kODAttributeTypeAuthenticationAuthority)
            print("Updated AuthenticationAuthority attribute successfully: \(newAuthorities)")
            message = newAuthorities
        } catch {
            return message
        }
        return message
    }
    
    func currentUser() -> String {
        var uid: uid_t = 0
        var gid: gid_t = 0
        var username = ""

        if let theResult = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) {
            username     = "\(theResult)"
            return username
        } else {
            WriteToLog.shared.message(stringOfText: "Unable to identify logged in user.")
            return ""
        }
    }
    
    func getUserRecord(username: String) throws -> ODRecord? {
        guard let session = ODSession.default() else {
            throw NSError(domain: "OpenDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Open Directory session."])
        }
            
        guard let node = try? ODNode(session: session, name: "/Search") else {
            throw NSError(domain: "OpenDirectory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to access local directory node."])
        }
        
        // Find the user record
        let query = try ODQuery(
            node: node,
            forRecordTypes: kODRecordTypeUsers,
            attribute: kODAttributeTypeRecordName,
            matchType: ODMatchType(kODMatchEqualTo),
            queryValues: username,
            returnAttributes: kODAttributeTypeNativeOnly,
            maximumResults: 1
        )
        
        guard let results = try query.resultsAllowingPartial(false) as? [ODRecord], let userRecord = results.first else {
            print("User not found: \(username).")
            throw NSError(domain: "OpenDirectory", code: 3, userInfo: [NSLocalizedDescriptionKey: "User not found."])
        }
        return nil
    }

    func isAdmin(username: String) -> Bool {
        do {
            // Open the local directory
            let session = ODSession.default()
            let node = try ODNode(session: session, name: "/Local/Default")
            
            // Get the admin group record
            let query = try node.record(withRecordType: kODRecordTypeGroups, name: "admin", attributes: nil)
            
            // Get the group members (this resolves nested memberships)
            if let members = try query.values(forAttribute: kODAttributeTypeGroupMembership) as? [String] {
                print("members: \(members)")
                return members.contains(username)
            }
            
            // Check nested groups (GroupMembers attribute resolves nested entries)
            if let nestedGroups = try query.values(forAttribute: kODAttributeTypeGroupMembers) as? [String] {
                print("nestedGroups: \(nestedGroups)")
                guard let userRecord = try getUserRecord(username: username) else {
                    return false
                }
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
    
    func passwordIsCorrect(username: String, password: String) -> Bool {
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
            
            // Attempt to verify the credentials
            try userRecord.verifyPassword(password)
            
            // If no exception is thrown, the credentials are correct
            return true
        } catch {
            WriteToLog.shared.message(stringOfText: "Authentication failed: \(error)")
            return false
        }
    }

    func updateAdminGroup(username: String, operation: String) -> Bool {
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

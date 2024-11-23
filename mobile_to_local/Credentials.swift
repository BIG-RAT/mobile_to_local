//
//  Credentials.swift
//  Mobile To Local
//
//  Copyright 2024 Jamf. All rights reserved.
//

import Foundation
import Security

let kSecAttrAccountString          = NSString(format: kSecAttrAccount)
let kSecValueDataString            = NSString(format: kSecValueData)
let kSecClassGenericPasswordString = NSString(format: kSecClassGenericPassword)
let keychainQ                      = DispatchQueue(label: "com.jamf.creds", qos: DispatchQoS.background)

let sharedPrefix                   = "MobileToLocal"
let accessGroup                    = "PS2F6S478M.jamfie.SharedJPMA"

class Credentials {
    
    static let shared = Credentials()
    
    var userPassDict = [String:String]()
    
    func save(service: String, account: String, credential: String, whichServer: String = "") {
        if service != "" && account != "" && service.first != "/" {
            let theService = sharedPrefix + "-" + service
            
            if let password = credential.data(using: String.Encoding.utf8) {
                keychainQ.async { [self] in
                    let keychainQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                                        kSecAttrService as String: theService,
                                                        kSecAttrAccessGroup as String: accessGroup,
                                                        kSecUseDataProtectionKeychain as String: true,
                                                        kSecAttrAccount as String: account,
                                                        kSecValueData as String: password]
                    
                    // see if credentials already exist for server
                    let accountCheck = checkExisting(service: theService, account: account)
                    if accountCheck.count == 1 {
                        if credential != accountCheck[account] {
                            // credentials already exist, try to update
                            let updateStatus = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueDataString:password] as [NSString : Any] as CFDictionary)
                            print("[Credentials.save] updateStatus for \(account) result: \(updateStatus)")
                            if updateStatus == 0 {
                                WriteToLog.shared.message(stringOfText: "keychain item for service \(theService), account \(account), has been updated.")
                            } else {
                                WriteToLog.shared.message(stringOfText: "keychain item for service \(theService), account \(account), failed to update.")
                            }
                        } else {
                            print("[Credentials.save] password for \(account) is up-to-date")
                        }
                    } else {
                        // try to add new credentials
                        let addStatus = SecItemAdd(keychainQuery as CFDictionary, nil)
                        if (addStatus != errSecSuccess) {
                            if let addErr = SecCopyErrorMessageString(addStatus, nil) {
                                print("[addStatus] Write failed for new credentials: \(addErr)")
                                let deleteStatus = SecItemDelete(keychainQuery as CFDictionary)
                                print("[Credentials.save] the deleteStatus: \(deleteStatus)")
                                sleep(1)
                                let addStatus = SecItemAdd(keychainQuery as CFDictionary, nil)
                                if (addStatus != errSecSuccess) {
                                    if let addErr = SecCopyErrorMessageString(addStatus, nil) {
                                        print("[addStatus] Write failed for new credentials after deleting: \(addErr)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }   // func save - end
    
    private func checkExisting(service: String, account: String) -> [String:String] {
        
        print("[Credentials.oldItemLookup] start search for: \(service)")
        
        userPassDict.removeAll()
        let keychainQuery: [String: Any] = [kSecClass as String: kSecClassGenericPasswordString,
                                            kSecAttrAccessGroup as String: accessGroup,
                                            kSecAttrService as String: service,
                                            kSecAttrAccount as String: account,
                                            kSecMatchLimit as String: kSecMatchLimitOne,
                                            kSecReturnAttributes as String: true,
                                            kSecReturnData as String: true]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            print("[Credentials.oldItemLookup] lookup error occurred: \(status.description)")
            return [:]
        }
        guard status == errSecSuccess else { return [:] }
        
        guard let existingItem = item as? [String : Any],
            let passwordData = existingItem[kSecValueData as String] as? Data,
//            let account = existingItem[kSecAttrAccount as String] as? String,
            let password = String(data: passwordData, encoding: String.Encoding.utf8)
        else {
            return [:]
        }
        userPassDict[account] = password
        return userPassDict
    }
    
    func retrieve(service: String, account: String, whichServer: String = "") -> [String:String] {
        
        var keychainResult = [String:String]()
        
//        print("[credentials] JamfProServer.sourceApiClient: \(JamfProServer.sourceUseApiClient)")
        
        userPassDict.removeAll()
        
        // look for common keychain item
        keychainResult = itemLookup(service: service)
        
        return keychainResult
    }
    
    private func itemLookup(service: String) -> [String:String] {
        
        print("[Credentials.itemLookup] start search for: \(service)")
        
        userPassDict.removeAll()
        let keychainQuery: [String: Any] = [kSecClass as String: kSecClassGenericPasswordString,
                                            kSecAttrService as String: service,
                                            kSecAttrAccessGroup as String: accessGroup,
                                            kSecUseDataProtectionKeychain as String: true,
                                            kSecMatchLimit as String: kSecMatchLimitAll,
                                            kSecReturnAttributes as String: true,
                                            kSecReturnData as String: true]
        
        var items_ref: CFTypeRef?
        
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &items_ref)

        guard status != errSecItemNotFound else {
            print("[Credentials.itemLookup] lookup error occurred for \(service): \(status.description)")
            return [:]
            
        }
        guard status == errSecSuccess else { return [:] }
        
        guard let items = items_ref as? [[String: Any]] else {
            print("[Credentials.itemLookup] unable to read keychain item: \(service)")
            return [:]
        }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, let passwordData = item[kSecValueData as String] as? Data {
                let password = String(data: passwordData, encoding: String.Encoding.utf8)
                userPassDict[account] = password ?? ""
            }
        }

//        print("[Credentials.itemLookup] keychain item count: \(userPassDict.count) for \(service)")
        return userPassDict
    }

}

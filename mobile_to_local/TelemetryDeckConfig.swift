//
//  Copyright © 2025 Jamf. All rights reserved.
//

import TelemetryDeck

struct TelemetryDeckConfig {
    static let appId = "***REMOVED***"
    @MainActor static var parameters: [String: String] = [:]
    @MainActor static var analytics: String = "enabled"
}

extension AppDelegate {
    @MainActor func configureTelemetryDeck() {
        
        if TelemetryDeckConfig.analytics != "disabled" {
            let config = TelemetryDeck.Config(appID: TelemetryDeckConfig.appId)
            TelemetryDeck.initialize(config: config)
        }
    }
}

import Foundation
@main struct SigningChecks {
    static func main() throws {
        let old = Date(timeIntervalSince1970:1000), new = Date(timeIntervalSince1970:2000)
        func profile(_ date: Date, app: String = "TEAM.com.example.ghost") throws -> Data {
            try PropertyListSerialization.data(fromPropertyList:["ExpirationDate":date,"Entitlements":["application-identifier":app]],format:.xml,options:0)
        }
        let p = try profile(new), oldProfile = try profile(old)
        precondition(AppSigningInfo.newerInstalledExpiry(profile:p,bundleIdentifier:"com.example.ghost",cached:old) == new)
        precondition(AppSigningInfo.newerInstalledExpiry(profile:oldProfile,bundleIdentifier:"com.example.ghost",cached:new) == nil)
        precondition(AppSigningInfo.newerInstalledExpiry(profile:p,bundleIdentifier:"com.example.other",cached:old) == nil)
        precondition(AppSigningInfo.newerInstalledExpiry(profile:nil,bundleIdentifier:"com.example.ghost",cached:old) == nil)
        precondition(AppSigningInfo.newerInstalledExpiry(profile:p,bundleIdentifier:"com.example.ghost",cached:nil) == new)
        print("Passed 5 signing refresh checks")
    }
}

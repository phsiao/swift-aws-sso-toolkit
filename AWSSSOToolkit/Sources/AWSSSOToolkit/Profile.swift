import Foundation

public enum AWSProfileType: Sendable {
  case SSO(session: AWSSSOSession, accountId: String, roleName: String, region: String)
}

public struct AWSSSOSession: Identifiable, Sendable {
  public let id = UUID()
  public let sessionName: String
  public let startUrl: String
  public let region: String
}

public struct AWSProfile: Identifiable, Sendable {
  public let id = UUID()
  public let profileName: String
  public let profileType: AWSProfileType
  public let region: String

  init(profileName: String, profileType: AWSProfileType, region: String) {
    self.profileName = profileName
    self.profileType = profileType
    self.region = region
  }
}

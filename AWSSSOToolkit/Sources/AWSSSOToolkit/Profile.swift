import Foundation

public enum AWSProfileType: Sendable {
  case SSO(session: AWSSSOSession, accountId: String, roleName: String, region: String)
}

public struct AWSSSOSession: Identifiable, Sendable {
  public let id = UUID()
  public let sessionName: String
  public let startUrl: String
  public let region: String

  public init(sessionName: String, startUrl: String, region: String) {
    self.sessionName = sessionName
    self.startUrl = startUrl
    self.region = region
  }
}

public struct AWSProfile: Identifiable, Sendable {
  public let id = UUID()
  public let profileName: String
  public let profileType: AWSProfileType
  public let region: String

  public init(profileName: String, profileType: AWSProfileType, region: String) {
    self.profileName = profileName
    self.profileType = profileType
    self.region = region
  }
}

public class ProfileState: Identifiable, Hashable {
  public let id = UUID()
  public let profile: AWSProfile
  public var identityResolver: InMemoryAWSSSOIdentityResolver?
  public var userArn: String?
  public var tokenExpiration: Date?
  public var credentialExpiration: Date?

  public init(profile: AWSProfile) {
    self.profile = profile
  }

  public static func == (lhs: ProfileState, rhs: ProfileState) -> Bool {
    return lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

@Observable
public class ProfileStore {
  public let profileStates: [ProfileState]

  public init(profileStates: [ProfileState]) {
    self.profileStates = profileStates
  }
}


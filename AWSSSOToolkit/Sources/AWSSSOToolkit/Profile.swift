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

final public class ProfileState: Identifiable, Hashable, Sendable {
  public let id = UUID()
  public let profile: AWSProfile
  public let identityResolver: InMemoryAWSSSOIdentityResolver
  @MainActor public var userArn: String?

  public init(profile: AWSProfile) {
    self.profile = profile
    self.identityResolver = InMemoryAWSSSOIdentityResolver(profile: profile)
  }

  public func tokenExpiration() async -> Date? {
    return await identityResolver.actor.tokenExpiration
  }

  public func credentialExpiration() async -> Date? {
    return await identityResolver.actor.credentialExpiration
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

import Foundation
import GRDB

/// AWS profile types supported by this package.
///  
/// Currently only SSO is supported and it is unlikely that more will be added.
public enum AWSProfileType: Sendable {
  /// Similar to a `profile` section in your `~/.aws/config` file,
  /// you must specify several arguments to use this profile type.
  case SSO(session: AWSSSOSession, accountId: String, roleName: String, region: String)
}

/// Represents an AWS SSO session.  This is the same concept as the `sso-session` section in your `~/.aws/config` file.
public struct AWSSSOSession: Identifiable, Sendable {
  public let id: String
  public let sessionName: String
  public let startUrl: String
  public let region: String

  public init(id: String = UUID().uuidString, sessionName: String, startUrl: String, region: String) {
    self.id = id
    self.sessionName = sessionName
    self.startUrl = startUrl
    self.region = region
  }
}

extension AWSSSOSession: Codable, FetchableRecord, PersistableRecord {
}

/// Represents an AWS profile.
/// - Parameters:
///   - profileName: The name of the profile.  The name must be unique among all profiles.
///   - profileType: The type of the profile.
public struct AWSProfile: Identifiable, Sendable {
  public let id: String
  public let profileName: String
  public let profileType: AWSProfileType

  public init(id: String = UUID().uuidString, profileName: String, profileType: AWSProfileType) {
    self.id = id
    self.profileName = profileName
    self.profileType = profileType
  }
}

/// Represents an AWS profile's state inside the application.
///
/// A profile, once declared, will have a state associated with it.  The state would include
/// the expiration times of the token and the credentials, as well as an identity resolver that
/// can be used to instantiate the API client with proper credentials.
final public class ProfileState: Identifiable, Hashable, Sendable {
  public let id: String
  public let profile: AWSProfile
  /// The identity resolver for this profile.
  public let identityResolver: InMemoryAWSSSOIdentityResolver

  public init(profile: AWSProfile) {
    self.id = profile.id
    self.profile = profile
    self.identityResolver = InMemoryAWSSSOIdentityResolver(profile: profile)
  }

  /// Get the expiration time of the device token.
  public func tokenExpiration() async -> Date? {
    return await identityResolver.actor.tokenExpiration
  }

  /// Get the expiration time of the temporary role credentials.
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

/// A store of profile states that this application is aware of.
public class ProfileStore {
  public var profileStates: [ProfileState]

  public init(profileStates: [ProfileState]) {
    self.profileStates = profileStates
  }
}

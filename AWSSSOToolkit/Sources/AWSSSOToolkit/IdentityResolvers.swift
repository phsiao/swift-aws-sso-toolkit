import Foundation
import protocol SmithyIdentity.AWSCredentialIdentityResolver
import struct SmithyIdentity.AWSCredentialIdentity
import struct Smithy.Attributes

/// An AWS credential identity that can be transmitted between actors or tasks.
public struct SendableAWSCredentialIdentity: Sendable {
  public let accessKey: String
  public let secret: String
  public let accountID: String?
  public let sessionToken: String?
  public let expiration: Date?
}

/// A credentials resolver for initializing AWS SDK clients.
///
/// This resolver is compatible with the `AWSCredentialIdentityResolver` protocol and stores temporary credentials in memory.
/// It does not depend on AWS CLI configuration files, making it suitable for environments where the AWS CLI is not installed or configured.
///
/// You can find this identity resolver in the ``ProfileState`` object.
public struct InMemoryAWSSSOIdentityResolver: AWSCredentialIdentityResolver, Sendable {
  private let profile: AWSProfile
  /// The actor responsible for handling the device authorization flow, including starting the authentication process and obtaining credentials.
  public let actor: SSODeviceAuthorizationFlowActor

  public init(profile: AWSProfile) {
    self.profile = profile
    self.actor = SSODeviceAuthorizationFlowActor(profile: profile)
  }

  public func getIdentity(identityProperties: Attributes? = nil) async throws -> AWSCredentialIdentity {
    // MARK: main entry point for getting valid credentials
    let credentials = try await actor.getRoleCredentials()
    return AWSCredentialIdentity(accessKey: credentials.accessKey,
                                 secret: credentials.secret,
                                 accountID: credentials.accountID,
                                 expiration: credentials.expiration,
                                 sessionToken: credentials.sessionToken)
  }
}

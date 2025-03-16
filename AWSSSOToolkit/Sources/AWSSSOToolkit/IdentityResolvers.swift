import Foundation
import protocol SmithyIdentity.AWSCredentialIdentityResolver
import struct SmithyIdentity.AWSCredentialIdentity
import struct Smithy.Attributes

public struct SendableAWSCredentialIdentity: Sendable {
  public let accessKey: String
  public let secret: String
  public let accountID: String?
  public let sessionToken: String?
  public let expiration: Date?
}

public struct InMemoryAWSSSOIdentityResolver: AWSCredentialIdentityResolver, Sendable {
  // MARK: this struct is compatible with AWSCredentialIdentityResolver but does not rely on files in ~/.aws/ to work
  private let profile: AWSProfile
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

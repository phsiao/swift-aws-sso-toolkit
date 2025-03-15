import Foundation
import struct SmithyIdentity.AWSCredentialIdentity
import AWSSSOOIDC
import AWSSSO
import struct os.Logger


public enum SSODeviceAuthorizationFlowActorError: Error {
  case runtimeError(String)
  case tokenExipred
  case invalidStateClientNotRegisterd
  case invalidStateDeviceNotAuthorized
  case invalidStateTokenNotCreated
}

public actor SSODeviceAuthorizationFlowActor {
  private let clientName: String
  private let logger: Logger
  private let profile: AWSProfile

  // private internal state
  private var ssoClientData: RegisterClientOutput? = nil
  private var deviceAuthData: StartDeviceAuthorizationOutput? = nil
  private var token: CreateTokenOutput? = nil

  private var _tokenExpiration: Date?
  public var tokenExpiration: Date? {
    get { return _tokenExpiration }
  }

  private var _credentialExpiration: Date?
  public var credentialExpiration: Date? {
    get { return _credentialExpiration }
  }

  public init(profile: AWSProfile, clientName: String = DefaultClientName) {
    self.profile = profile
    self.clientName = clientName
    self.logger = Logger(subsystem: DefaultSubsystemName,
                         category: String(describing: SSODeviceAuthorizationFlowActor.self))
  }

  // setupAuth() attempts to:
  //   1. register this as a client
  //   2. start device authorization process using the registered client
  // to finish the setup, the returned URL must be open in a browser and for the user
  // to finish the login.
  //
  // You can start getToken() after this step, though the token would only
  // become available once the user finishes the login.
  public func setupAuth() async throws -> URL {
    switch profile.profileType {
    case .SSO(session: let session, accountId: _, roleName: _, region: let region):
      let ssoOidcClient = try SSOOIDCClient(region: region)

      logger.trace("calling registerClient")
      ssoClientData = try await ssoOidcClient.registerClient(
        input: RegisterClientInput(
          clientName: clientName,
          clientType: "public",
          grantTypes: ["refresh_token"]
        )
      )
      logger.trace("done")

      guard let ssoClientData = ssoClientData else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError("registerClient returns nil")
      }

      // logger.debug("ssoClientData: \(String(describing: ssoClientData))")
      logger.trace("calling startDeviceAuthorization")
      deviceAuthData = try await ssoOidcClient.startDeviceAuthorization(
        input: StartDeviceAuthorizationInput(
          clientId: ssoClientData.clientId,
          clientSecret: ssoClientData.clientSecret,
          startUrl: session.startUrl)
      )
      logger.trace("done")

      guard let deviceAuthData = deviceAuthData else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError("error calling startDeviceAuthorization")
      }
      logger.debug("deviceAuth: \(String(describing: deviceAuthData))")
      guard let verificationUri = deviceAuthData.verificationUriComplete else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError("startDeviceAuthorization must not return nil verification URI")
      }
      guard let url = URL(string: verificationUri) else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError("verification URI (\(verificationUri) is not a valid URL")
      }
      return url
    }
  }

  public func getToken() async throws {
    let startDate = Date()
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoOidcClient = try SSOOIDCClient(region: region)

      for _ in 1...30 {
        let seconds = 5.0
        // sleep for 5 second
        try await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
        do {
          token = try await ssoOidcClient.createToken(
            input: CreateTokenInput(
              clientId: ssoClientData!.clientId,
              clientSecret: ssoClientData!.clientSecret,
              deviceCode: deviceAuthData!.deviceCode,
              grantType: "urn:ietf:params:oauth:grant-type:device_code"
            )
          )
          break
        } catch {
          // FIXME: should only continue if it is retriable error
          logger.error("error: \(error)")
          continue
        }
      }

      guard let token = token else {
        logger.error("cannot get token")
        return
      }
      logger.info("\(String(describing: token))")
      _tokenExpiration = startDate.addingTimeInterval(TimeInterval(token.expiresIn))
    }
  }

  public func getRoleCredentials() async throws -> SendableAWSCredentialIdentity {
    guard let _ = ssoClientData else {
      throw SSODeviceAuthorizationFlowActorError.invalidStateClientNotRegisterd
    }
    guard let _ = deviceAuthData else {
      throw SSODeviceAuthorizationFlowActorError.invalidStateDeviceNotAuthorized
    }
    guard let token = token else {
      throw SSODeviceAuthorizationFlowActorError.invalidStateTokenNotCreated
    }

    switch profile.profileType {
    case .SSO(session: _, accountId: let accountId, roleName: let roleName, region: let region):
      let ssoClient = try SSOClient(region: region)
      let response = try await ssoClient.getRoleCredentials(
        input: GetRoleCredentialsInput(
          accessToken: token.accessToken,
          accountId: accountId,
          roleName: roleName
        )
      )
      logger.debug("\(String(describing: response))")

      guard let roleCredentials = response.roleCredentials else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError("roleCredentials can not be nil in getRoleCredentials response")
      }
      _credentialExpiration = Date(timeIntervalSince1970: Double(roleCredentials.expiration)/1000.0)
      let credentials = SendableAWSCredentialIdentity(
        accessKey: roleCredentials.accessKeyId!,
        secret: roleCredentials.secretAccessKey!,
        accountID: nil,
        sessionToken: roleCredentials.sessionToken,
        expiration: _credentialExpiration
      )
      return credentials
    }
  }
}

extension SSODeviceAuthorizationFlowActor {
  // MARK: - extra functionalities of the actor
  public func getAccounts() async throws -> [SSOClientTypes.AccountInfo]? {
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoClient = try SSOClient(region: region)
      let accounts = try await ssoClient.listAccounts(input: ListAccountsInput(accessToken: token?.accessToken))
      logger.debug("\(String(describing: accounts))")
      return accounts.accountList
    }
  }

  public func getAccountRoles(accountId: String) async throws -> [SSOClientTypes.RoleInfo]? {
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoClient = try SSOClient(region: region)
      let response = try await ssoClient.listAccountRoles(input: ListAccountRolesInput(accessToken: token?.accessToken, accountId: accountId))
      logger.info("\(String(describing: response))")
      return response.roleList
    }
  }
}


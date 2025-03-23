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

/// An actor that handles the device authorization flow for AWS SSO.
///
/// This actor is responsible for registering the client, starting the device authorization process, and obtaining
/// role credentials. Swift actor is used to make sure the internal state is not shared between multiple threads.
public actor SSODeviceAuthorizationFlowActor {
  private let clientName: String
  private let logger: Logger
  private let profile: AWSProfile

  // private internal state
  private var ssoClientData: RegisterClientOutput?
  private var deviceAuthData: StartDeviceAuthorizationOutput?
  private var token: CreateTokenOutput?
  private var roleCredentials: GetRoleCredentialsOutput?

  private var _tokenExpiration: Date?
  /// The expiration date of the device token.
  public var tokenExpiration: Date? {
    return _tokenExpiration
  }

  private var _credentialExpiration: Date?
  /// The expiration date of the temporary role credentials
  public var credentialExpiration: Date? {
    return _credentialExpiration
  }

  public init(profile: AWSProfile, clientName: String = defaultClientName) {
    self.profile = profile
    self.clientName = clientName
    self.logger = Logger(subsystem: defaultSubsystemName,
                         category: String(describing: SSODeviceAuthorizationFlowActor.self))
  }

  /// Set up the authentication flow.
  ///
  /// `setupAuth()` attempts to:
  ///   1. register this as a client
  ///   2. start device authorization process using the registered client
  /// to finish the setup, the returned URL must be open in a browser and for the user
  /// to finish the login.
  ///
  /// You can start ``getToken()`` after this step, though the token would only become available once the user
  /// finishes the login.
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
      // logger.debug("deviceAuth: \(String(describing: deviceAuthData))")
      guard let verificationUri = deviceAuthData.verificationUriComplete else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError(
          "startDeviceAuthorization must not return nil verification URI"
        )
      }
      guard let url = URL(string: verificationUri) else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError(
          "verification URI (\(verificationUri) is not a valid URL"
        )
      }
      return url
    }
  }

  /// Get the token after the user finishes the login.
  ///
  /// It continues to poll the server every 5 seconds for 30 times to get the token.
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
          switch error {
          case _ as AWSSSOOIDC.AuthorizationPendingException:
            // retryable error as device auth is pending
            logger.trace("user auth pending, retrying")
            continue
          default:
            logger.error("error: \(error)")
            throw error
          }
        }
      }

      guard let token = token else {
        logger.error("cannot get token")
        return
      }
      logger.trace("\(String(describing: token))")
      _tokenExpiration = startDate.addingTimeInterval(TimeInterval(token.expiresIn))
    }
  }

  private func transformRoleCredentials(roleCredentials: GetRoleCredentialsOutput) -> SendableAWSCredentialIdentity {
    guard let roleCredentials = roleCredentials.roleCredentials else {
      fatalError("roleCredentials can not be nil in getRoleCredentials response")
    }
    return SendableAWSCredentialIdentity(
      accessKey: roleCredentials.accessKeyId!,
      secret: roleCredentials.secretAccessKey!,
      accountID: roleCredentials.accessKeyId,
      sessionToken: roleCredentials.sessionToken,
      expiration: _credentialExpiration
    )
  }

  /// This function attempts to get the role credentials for the given profile and returns the credentials in
  /// sendable format.
  ///
  /// This allows the IdennityResolver to get the credentials crossing the actor boundary.
  /// It also caches the role credentials for future use, and would only get the new credentials if the cached one
  /// is expired.
  public func getRoleCredentials() async throws -> SendableAWSCredentialIdentity {
    switch profile.profileType {
    case .SSO(session: _, accountId: let accountId, roleName: let roleName, region: let region):
      if ssoClientData == nil {
        throw SSODeviceAuthorizationFlowActorError.invalidStateClientNotRegisterd
      }
      if deviceAuthData == nil {
        throw SSODeviceAuthorizationFlowActorError.invalidStateDeviceNotAuthorized
      }

      // use cached roleCredentials if it is not expired
      // note that the cached roleCredentials can still be valid even after logout or token expiration
      if let expiration = _credentialExpiration, expiration > Date() && roleCredentials != nil {
        logger.debug("using cached roleCredentials")
        return transformRoleCredentials(roleCredentials: roleCredentials!)
      }

      guard let token = token else {
        throw SSODeviceAuthorizationFlowActorError.invalidStateTokenNotCreated
      }

      if let expiration = _tokenExpiration, expiration < Date() {
        self.token = nil
        throw SSODeviceAuthorizationFlowActorError.tokenExipred
      }

      let ssoClient = try SSOClient(region: region)
      roleCredentials = try await ssoClient.getRoleCredentials(
        input: GetRoleCredentialsInput(
          accessToken: token.accessToken,
          accountId: accountId,
          roleName: roleName
        )
      )
      logger.debug("\(String(describing: self.roleCredentials))")

      guard let roleCred = self.roleCredentials!.roleCredentials else {
        throw SSODeviceAuthorizationFlowActorError.runtimeError(
          "roleCredentials can not be nil in getRoleCredentials response"
        )
      }
      _credentialExpiration = Date(timeIntervalSince1970: Double(roleCred.expiration)/1000.0)
      return transformRoleCredentials(roleCredentials: self.roleCredentials!)
    }
  }
}

extension SSODeviceAuthorizationFlowActor {
  // MARK: - extra functionalities of the actor
  /// Get a list of AWS accounts that this SSO session can access.
  public func getAccounts() async throws -> [SSOClientTypes.AccountInfo]? {
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoClient = try SSOClient(region: region)
      let accounts = try await ssoClient.listAccounts(input: ListAccountsInput(accessToken: token?.accessToken))
      logger.debug("\(String(describing: accounts))")
      return accounts.accountList
    }
  }

  /// Get an list of roles that the given account can assume.
  public func getAccountRoles(accountId: String) async throws -> [SSOClientTypes.RoleInfo]? {
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoClient = try SSOClient(region: region)
      let response = try await ssoClient.listAccountRoles(
        input: ListAccountRolesInput(accessToken: token?.accessToken, accountId: accountId))
      logger.info("\(String(describing: response))")
      return response.roleList
    }
  }

  /// Log out of the SSO session.
  public func logout() async throws {
    switch profile.profileType {
    case .SSO(session: _, accountId: _, roleName: _, region: let region):
      let ssoClient = try SSOClient(region: region)
      if let token = token {
        logger.info("logout requested")
        _ = try await ssoClient.logout(input: LogoutInput(accessToken: token.accessToken))
        self.token = nil
        self._tokenExpiration = nil
      }
    }
  }

  /// Forget the cached role credentials.
  public func forgetRoleCredentials() {
    if self.roleCredentials != nil {
      logger.info("forget cached roleCredentials")
      self.roleCredentials = nil
      self._credentialExpiration = nil
    }
  }
}

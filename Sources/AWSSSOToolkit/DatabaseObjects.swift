import Foundation
import GRDB

/// A struct that represents an AWS SSO profile in the database.
struct AWSSSOProfile: Identifiable, Sendable {
  let id: String
  let profileName: String
  let awsssoSessionId: String
  let accountId: String
  let roleName: String
  let region: String

  init(from: AWSProfile) {
    self.id = from.id
    self.profileName = from.profileName
    switch from.profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      self.awsssoSessionId = session.id
      self.accountId = accountId
      self.roleName = roleName
      self.region = region
    }
  }

  func toAWSProfile(dbQueue: DatabaseQueue) throws -> AWSProfile {
    let ssoSessionId = self.awsssoSessionId
    let ssoSession = try dbQueue.read { dbq in
      try AWSSSOSession.filter(key: ssoSessionId).fetchOne(dbq)
    }
    let type = AWSProfileType.SSO(session: ssoSession!,
                                  accountId: self.accountId,
                                  roleName: self.roleName,
                                  region: self.region)

    return AWSProfile(id: self.id,
                      profileName: self.profileName,
                      profileType: type
    )
  }
}

extension AWSSSOProfile: Codable, FetchableRecord, PersistableRecord {
}

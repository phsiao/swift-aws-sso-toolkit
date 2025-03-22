import Foundation
import GRDB
import Testing

@testable import AWSSSOToolkit

@Test("BackingDatabase getDatabasePath() should return expected file path")
func dbpathTest() throws {
  let db1 = BackingDatabase(identifier: "foo", dbFileName: "bar.sqlite")
  let url1 = try db1.getDatabaseFilePath()
  #expect(url1.path().hasSuffix("/foo/bar.sqlite"))
  let db2 = BackingDatabase(identifier: "foo", dbFileName: "xyz.sqlite")
  let url2 = try db2.getDatabaseFilePath()
  #expect(url2.path().hasSuffix("/foo/xyz.sqlite"))
}

@Test("BackingDatabase can save and load AWSSSOSession")
func AWSSSOSessionTest() throws {
  let session = AWSSSOSession(sessionName: "foo", startUrl: "bar", region: "us-west-2")
  #expect(session.sessionName == "foo")
  #expect(session.startUrl == "bar")
  #expect(session.region == "us-west-2")

  let db = BackingDatabase(
    identifier: "awsssotoolkit-test-session-delete", dbFileName: "db-session.sqlite")
  try db.migrate()

  let dbQueue = try db.getDbQueue()
  try dbQueue.write { db in
    try session.insert(db)
  }

  let sessions = try dbQueue.read { db in
    try AWSSSOSession.fetchAll(db)
  }
  #expect(sessions.count == 1)
  #expect(sessions[0].sessionName == "foo")
  #expect(sessions[0].startUrl == "bar")
  #expect(sessions[0].region == "us-west-2")

  try dbQueue.close()
  try FileManager.default.removeItem(at: try db.getDatabaseFilePath())
  try FileManager.default.removeItem(at: try db.getDatabaseFileDir())
}

@Test("BackingDatabase can save and load AWSProfile")
func AWSProfileTest() throws {
  let db = BackingDatabase(
    identifier: "awsssotoolkit-test-profile-delete", dbFileName: "db-profile.sqlite")
  try db.migrate()

  let session = AWSSSOSession(sessionName: "foo", startUrl: "bar", region: "us-west-2")

  var config = Configuration()
  config.prepareDatabase { db in
    // db.trace { print($0) }
  }
  let dbQueue = try db.getDbQueue(configuration: config)
  try dbQueue.write { db in
    try session.insert(db)
  }

  let profile = AWSProfile(
    profileName: "test",
    profileType: .SSO(session: session, accountId: "123", roleName: "admin", region: "us-west-2"))
  let ssoProfile = AWSSSOProfile(from: profile)
  try dbQueue.write { db in
    try ssoProfile.insert(db)
  }

  let ssoProfiles = try dbQueue.read { db in
    try AWSSSOProfile.fetchAll(db)
  }
  #expect(ssoProfiles.count == 1)
  #expect(ssoProfiles[0].profileName == "test")
  #expect(ssoProfiles[0].accountId == "123")
  #expect(ssoProfiles[0].roleName == "admin")
  #expect(ssoProfiles[0].region == "us-west-2")

  let rtProfile = try ssoProfiles[0].toAWSProfile(dbQueue: dbQueue)
  #expect(rtProfile.profileName == "test")
  #expect(rtProfile.id == ssoProfiles[0].id)
  switch rtProfile.profileType {
  case .SSO(let session, let accountId, let roleName, let region):
    #expect(session.sessionName == "foo")
    #expect(session.startUrl == "bar")
    #expect(session.region == "us-west-2")
    #expect(accountId == "123")
    #expect(roleName == "admin")
    #expect(region == "us-west-2")
  }

  try dbQueue.close()
  try FileManager.default.removeItem(at: try db.getDatabaseFilePath())
  try FileManager.default.removeItem(at: try db.getDatabaseFileDir())
}

@Test("BackingDatabse should handle multiple AWSSSOProfiles")
func AWSProfilesTest() throws {
  let db = BackingDatabase(
    identifier: "awsssotoolkit-test-profiles-delete", dbFileName: "db-profiles.sqlite")
  try db.migrate()

  let session1 = AWSSSOSession(sessionName: "foo1", startUrl: "bar1", region: "us-west-2")
  let session2 = AWSSSOSession(sessionName: "foo2", startUrl: "bar2", region: "us-east-2")

  let profile1 = AWSProfile(
    profileName: "test1",
    profileType: .SSO(session: session1, accountId: "123", roleName: "admin", region: "us-west-2"))
  let profile2 = AWSProfile(
    profileName: "test2",
    profileType: .SSO(session: session2, accountId: "123", roleName: "admin", region: "us-west-2"))
  let profile3 = AWSProfile(
    profileName: "test3",
    profileType: .SSO(session: session2, accountId: "123", roleName: "admin", region: "us-east-1"))

  var config = Configuration()
  config.prepareDatabase { db in
    // db.trace { print($0) }
  }
  let dbQueue = try db.getDbQueue(configuration: config)

  do {
    // write first 2 profiles
    try db.save(profiles: [profile1, profile2])
    let profiles = try db.load()

    #expect(profiles.count == 2)
    #expect(profiles[0].profileName == "test1")
    switch profiles[0].profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      #expect(session.sessionName == "foo1")
      #expect(session.startUrl == "bar1")
      #expect(session.region == "us-west-2")
      #expect(accountId == "123")
      #expect(roleName == "admin")
      #expect(region == "us-west-2")
    }
    #expect(profiles[1].profileName == "test2")
    switch profiles[1].profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      #expect(session.sessionName == "foo2")
      #expect(session.startUrl == "bar2")
      #expect(session.region == "us-east-2")
      #expect(accountId == "123")
      #expect(roleName == "admin")
      #expect(region == "us-west-2")
    }
  } catch {
    print("error: \(error)")
  }

  do {
    // write all three profiles
    try db.save(profiles: [profile1, profile2, profile3])
    let profiles = try db.load()

    #expect(profiles.count == 3)
    #expect(profiles[0].profileName == "test1")
    switch profiles[0].profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      #expect(session.sessionName == "foo1")
      #expect(session.startUrl == "bar1")
      #expect(session.region == "us-west-2")
      #expect(accountId == "123")
      #expect(roleName == "admin")
      #expect(region == "us-west-2")
    }
    #expect(profiles[1].profileName == "test2")
    switch profiles[1].profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      #expect(session.sessionName == "foo2")
      #expect(session.startUrl == "bar2")
      #expect(session.region == "us-east-2")
      #expect(accountId == "123")
      #expect(roleName == "admin")
      #expect(region == "us-west-2")
    }
    #expect(profiles[2].profileName == "test3")
    switch profiles[2].profileType {
    case .SSO(let session, let accountId, let roleName, let region):
      #expect(session.sessionName == "foo2")
      #expect(session.startUrl == "bar2")
      #expect(session.region == "us-east-2")
      #expect(accountId == "123")
      #expect(roleName == "admin")
      #expect(region == "us-east-1")
    }
  } catch {
    print("error: \(error)")
  }

  try dbQueue.close()
  try FileManager.default.removeItem(at: try db.getDatabaseFilePath())
  try FileManager.default.removeItem(at: try db.getDatabaseFileDir())
}

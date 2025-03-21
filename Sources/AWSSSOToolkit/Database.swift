import Foundation
import GRDB

/// A backing database for storing SSO session and profile configurations.
///
/// This database uses [GRDB](https://github.com/groue/GRDB.swift) for implementation.
///
/// Note: Device tokens or role credentials are not stored in the database. Users will need to re-authenticate
/// if the application is restarted.
public struct BackingDatabase: Sendable {
  /// The identifier of the database, used to create a folder in the Application Support directory.
  public let identifier: String
  /// The name of the database file in the Application Support directory.
  public let dbFileName: String

  public init(identifier: String, dbFileName: String = "awsssotoolkit.sqlite") {
    self.identifier = identifier
    self.dbFileName = dbFileName
  }

  public func getDatabaseFileDir() throws -> URL {
    let applicationSupportFolderURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true)
    let folder = applicationSupportFolderURL.appendingPathComponent("\(self.identifier)/", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
    }
    return folder
  }

  public func getDatabaseFilePath() throws -> URL {
    let applicationSupportFolderURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true)
    let folder = applicationSupportFolderURL.appendingPathComponent("\(self.identifier)/", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
    }
    let databaseURL = folder.appendingPathComponent(self.dbFileName)
    return databaseURL
  }

  public func deleteDatabase() throws {
    try FileManager.default.removeItem(at: try self.getDatabaseFilePath())
    try FileManager.default.removeItem(at: try self.getDatabaseFileDir())
  }

  public func getDbQueue(configuration: Configuration = Configuration()) throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue(path: self.getDatabaseFilePath().absoluteString, configuration: configuration)
    return dbQueue
  }
}

// MARK: - DatabaseMigrator
extension BackingDatabase {
  /// Migrates the database to the latest schema.
  public func migrate() throws {
    let dbqueue = try self.getDbQueue()
    try self.migration(dbqueue)
    try dbqueue.close()
  }
  func migration(_ dbqueue: DatabaseQueue) throws {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("Create awsssoSession and awsProfile table") { dbq in
      try dbq.create(table: "awsssoSession") { tbl in
        tbl.column("id", .text).primaryKey().notNull()
        tbl.column("sessionName", .text).unique().notNull()
        tbl.column("startUrl", .text).notNull()
        tbl.column("region", .text).notNull()
      }
      try dbq.create(table: "awsssoProfile") { tbl in
        tbl.column("id", .text).primaryKey().notNull()
        tbl.column("profileName", .text).unique().notNull()
        tbl.column("accountId", .text).notNull()
        tbl.column("roleName", .text).notNull()
        tbl.column("region", .text).notNull()
        tbl.belongsTo("awsssoSession", onDelete: .cascade).notNull()
      }
    }

    try migrator.migrate(dbqueue)
  }
}

extension BackingDatabase {
  /// Save a  list of profiles to the database.
  public func save(profiles: [AWSProfile]) throws {
    try self.migrate()
    let dbQueue = try self.getDbQueue()

    let ssoSessions = profiles.compactMap { profile -> AWSSSOSession? in
      guard case .SSO(let session, _, _, _) = profile.profileType else {
        return nil
      }
      return session
    }
    try dbQueue.write { dbq in
      for session in ssoSessions {
        try session.upsert(dbq)
      }
    }

    let ssoProfiles = profiles.map { AWSSSOProfile(from: $0) }
    try dbQueue.write { dbq in
      for profile in ssoProfiles {
        try profile.upsert(dbq)
      }
    }
  }

  /// Load the list of profiles from the database.
  public func load() throws -> [AWSProfile] {
    try self.migrate()
    let dbQueue = try self.getDbQueue()
    let ssoProfiles = try dbQueue.read { dbq in
      try AWSSSOProfile.order(Column("profileName")).fetchAll(dbq)
    }
    let profiles = try ssoProfiles.map { profile -> AWSProfile in
      try profile.toAWSProfile(dbQueue: dbQueue)
    }
    return profiles
  }
}

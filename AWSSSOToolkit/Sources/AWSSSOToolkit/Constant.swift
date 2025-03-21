/// The default subsystem name for the package.  Mainly used in logging.
public let defaultSubsystemName: String = "AWSSSOToolkit"

/// The default client name for the package.  Used in the SSO flow.
public let defaultClientName: String = "AWSSSOToolkit"

public struct Region: Identifiable, Sendable {
  public let region: String
  public var id: String { region }
}

/// A list of AWS regions, for use in drop-down menus.
public let awsRegionList: [Region] = [
  Region(region: "af-south-1"),
  Region(region: "ap-east-1"),
  Region(region: "ap-northeast-1"),
  Region(region: "ap-northeast-2"),
  Region(region: "ap-northeast-3"),
  Region(region: "ap-south-1"),
  Region(region: "ap-south-2"),
  Region(region: "ap-southeast-1"),
  Region(region: "ap-southeast-2"),
  Region(region: "ap-southeast-3"),
  Region(region: "ap-southeast-4"),
  Region(region: "ap-southeast-5"),
  Region(region: "ap-southeast-7"),
  Region(region: "ca-central-1"),
  Region(region: "ca-west-1"),
  Region(region: "cn-north-1"),
  Region(region: "cn-northwest-1"),
  Region(region: "eu-central-1"),
  Region(region: "eu-central-2"),
  Region(region: "eu-north-1"),
  Region(region: "eu-south-1"),
  Region(region: "eu-south-2"),
  Region(region: "eu-west-1"),
  Region(region: "eu-west-2"),
  Region(region: "eu-west-3"),
  Region(region: "il-central-1"),
  Region(region: "me-central-1"),
  Region(region: "me-south-1"),
  Region(region: "mx-central-1"),
  Region(region: "sa-east-1"),
  Region(region: "us-east-1"),
  Region(region: "us-east-2"),
  Region(region: "us-gov-east-1"),
  Region(region: "us-gov-west-1"),
  Region(region: "us-west-1"),
  Region(region: "us-west-2")
]

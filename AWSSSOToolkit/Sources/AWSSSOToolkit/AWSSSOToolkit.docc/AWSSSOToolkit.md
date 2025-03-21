# ``AWSSSOToolkit``

Managing AWS SSO credentials in your application can be challenging. This toolkit simplifies
the process by providing tools to better integrate AWS SSO credentials into your application.

## Overview

Most applications that integrate with AWS SSO use the AWS CLI to obtain temporary credentials,
which can be cumbersome for several reasons:

1. The common method involves using the `aws sso login` command to get temporary credentials.
   This is a manual process that the user must initiate outside of the application, and the
   user is required to configure the CLI with the appropriate profile. This can be cumbersome
   and the application cannot assist.
2. The credentials are stored in the `~/.aws` directory, and the application must read them
   from these files. For sandboxed or containerized applications, accessing these credentials
   can be difficult.

This toolkit allows you to manage AWS SSO credentials in your application without relying on
the AWS CLI. It enables authentication with AWS SSO, obtaining temporary credentials, and
storing them in a manner that your application can utilize. Additionally, it offers a SwiftUI
view to assist in configuring AWS SSO profiles and authenticating with AWS SSO.

## Topics

### Essentials

- ``AWSProfile``
- ``InMemoryAWSSSOIdentityResolver``
- ``AWSSSOProfilesView``


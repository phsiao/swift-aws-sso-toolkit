import Testing

@testable import AWSSSOToolkit

@Test("SSOSessionForm is complete when requirements are met")
func SSOSessionFormTest() throws {
  let sessionForm = SSOSessionForm()
  #expect(sessionForm.isFormComplete == false)

  sessionForm.ssoSessionName = "testname"
  #expect(sessionForm.isFormComplete == false)

  sessionForm.region = "us-east-1"
  #expect(sessionForm.isFormComplete == false)

  sessionForm.startUrl = "https://foo.awsapps.com/start"
  #expect(sessionForm.isFormComplete == true)

  sessionForm.region = ""
  #expect(sessionForm.isFormComplete == false)

  sessionForm.startUrl = "127.0.0.1:8000/test"
  #expect(sessionForm.isFormComplete == false)
}

@Test("ProfileForm is complete when requirements are met")
func ProfileFormTest() throws {
  let ssoSession = AWSSSOSession(
    sessionName: "testname",
    startUrl: "https://foo/start",
    region: "us-east-1")

  let profileForm = ProfileForm()
  #expect(profileForm.isFormComplete == false)

  profileForm.ssoSession = ssoSession
  #expect(profileForm.isFormComplete == false)

  profileForm.profileName = "testname"
  #expect(profileForm.isFormComplete == false)

  profileForm.region = "us-east-1"
  #expect(profileForm.isFormComplete == false)

  profileForm.accountId = "123456789012"
  #expect(profileForm.isFormComplete == false)

  profileForm.roleName = "testrole"
  #expect(profileForm.isFormComplete == true)

}

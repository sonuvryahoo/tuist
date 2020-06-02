import Foundation
import TuistCore

protocol SigningLinting {
    func lint(certificate: Certificate, provisioningProfile: ProvisioningProfile) -> [LintingIssue]
}

final class SigningLinter: SigningLinting {
    func lint(certificate: Certificate, provisioningProfile: ProvisioningProfile) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if certificate.developmentTeam != provisioningProfile.teamId {
            let reason: String = """
            Certificate \(certificate.name)'s development team \(certificate.developmentTeam) does not correspond to \(provisioningProfile.teamId).
            Make sure they are the same.
            """
            issues.append(LintingIssue(reason: reason, severity: .error))
        }
        
        return issues
    }
}

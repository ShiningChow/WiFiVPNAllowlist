import AppKit
import Foundation
import VPNGuardCore

struct VPNApplicationEnforcementOutcome: Sendable {
    var terminatedNames: [String]
    var forceTerminatedNames: [String]
    var failedNames: [String]
    var runningNames: [String]
}

@MainActor
enum VPNApplicationController {
    static func inspect(
        applications: [ManagedVPNApplication]
    ) -> VPNApplicationEnforcementOutcome {
        let runningNames = applications.filter(\.isEnabled).filter { application in
            !runningApplications(for: application.bundleIdentifier).isEmpty
        }.map(\.displayName)

        return VPNApplicationEnforcementOutcome(
            terminatedNames: [],
            forceTerminatedNames: [],
            failedNames: [],
            runningNames: runningNames
        )
    }

    static func terminate(
        applications: [ManagedVPNApplication]
    ) async -> VPNApplicationEnforcementOutcome {
        let enabled = applications.filter(\.isEnabled)
        let targets = enabled.flatMap { application in
            runningApplications(for: application.bundleIdentifier).map { running in
                (application, running)
            }
        }.filter { _, running in
            running.bundleIdentifier != Bundle.main.bundleIdentifier
        }

        guard !targets.isEmpty else {
            return inspect(applications: applications)
        }

        var terminatedNames: [String] = []
        var forceTerminatedNames: [String] = []
        var failedNames: [String] = []

        for (application, running) in targets {
            if running.terminate() {
                terminatedNames.append(application.displayName)
            } else if running.forceTerminate() {
                forceTerminatedNames.append(application.displayName)
            } else {
                failedNames.append(application.displayName)
            }
        }

        try? await Task.sleep(for: .milliseconds(900))

        for application in enabled {
            let survivors = runningApplications(for: application.bundleIdentifier)
            guard !survivors.isEmpty else {
                continue
            }
            var forcedAtLeastOne = false
            for running in survivors where running.bundleIdentifier != Bundle.main.bundleIdentifier {
                forcedAtLeastOne = running.forceTerminate() || forcedAtLeastOne
            }
            if forcedAtLeastOne && !forceTerminatedNames.contains(application.displayName) {
                forceTerminatedNames.append(application.displayName)
            }
        }

        try? await Task.sleep(for: .milliseconds(300))
        let runningNames = enabled.filter { application in
            !runningApplications(for: application.bundleIdentifier).isEmpty
        }.map(\.displayName)

        for name in runningNames where !failedNames.contains(name) {
            failedNames.append(name)
        }

        return VPNApplicationEnforcementOutcome(
            terminatedNames: Array(Set(terminatedNames)).sorted(),
            forceTerminatedNames: Array(Set(forceTerminatedNames)).sorted(),
            failedNames: Array(Set(failedNames)).sorted(),
            runningNames: Array(Set(runningNames)).sorted()
        )
    }

    private static func runningApplications(for bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
    }
}

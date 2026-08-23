import Foundation

// Standalone compatibility shim for compiling the provider service without the app target.
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case decodingError(Error)
    case unsupported
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        default: return String(describing: self)
        }
    }
}

@main
enum OpenCodeGoUsageProbe {
    static func main() throws {
        let service = OpenCodeGoUsageService.shared

        let rawTokenCookie = try service.normalizedCookieHeader("Fe26.2**token")
        precondition(rawTokenCookie == "auth=Fe26.2**token")
        let hostCookie = try service.normalizedCookieHeader(
            "theme=dark; __Host-auth=session; ignored=value"
        )
        precondition(hostCookie == "__Host-auth=session")
        precondition(
            service.parseWorkspaceIDs(#"{workspaces:[{id:"wrk_ABC123"},{id:'wk_Z9'}]}"#)
                == ["wrk_ABC123", "wk_Z9"]
        )

        let dashboardHTML = #"""
        <script>window.data={
          rollingUsage:{usagePercent:12,resetInSec:1800},
          weeklyUsage:{usagePercent:34.4,resetInSec:259200},
          monthlyUsage:{usagePercent:56,resetInSec:1728000}
        }</script>
        """#
        let dashboard = try service.parseDashboardUsage(dashboardHTML)
        precondition(dashboard.planType == "OpenCode Go")
        precondition(dashboard.rateLimit?.primaryWindow?.usedPercent == 12)
        precondition(dashboard.rateLimit?.secondaryWindow?.usedPercent == 34)
        precondition(dashboard.rateLimit?.tertiaryWindow?.usedPercent == 56)

        let quotedDashboard = try service.parseDashboardUsage(
            #"{"rollingUsage":{"usagePercent":1,"resetInSec":60},"weeklyUsage":{"usagePercent":2,"resetInSec":120}}"#
        )
        precondition(quotedDashboard.rateLimit?.primaryWindow?.usedPercent == 1)
        precondition(quotedDashboard.rateLimit?.secondaryWindow?.usedPercent == 2)

        do {
            _ = try service.parseDashboardUsage(
                "rollingUsage:{usagePercent:12,resetInSec:1800}"
            )
            preconditionFailure("Weekly usage must be required")
        } catch { }

        print("OpenCode Go authoritative dashboard parser probe passed")
    }
}

# Luxquare

A lightweight native iPhone and iPad workspace. SwiftUI provides navigation and Liquid Glass on iOS 26 or later, with material fallbacks on iOS 17–25.

The app reads the authenticated workbench catalog rather than maintaining a second module registry. Existing web modules retain their own origins, SSO, business data and permissions. Native tools include local microphone recording with account-scoped drafts, deliberate upload, location, file downloads and system sharing. The native dialogue connects to the existing SSE service and keeps its own local history.

Generate the project with XcodeGen and build the Luxquare scheme. The macOS script builds an unsigned device package and runs the actual parser, request-isolation and simulator UI checks. UI testing uses inert sample data and does not contact a business service.

This public client has no deployed server configuration, signing materials or owner session. Deployment values are injected locally after the generic build. First account login, hardware permissions and iOS installation confirmations remain under the device owner's control.

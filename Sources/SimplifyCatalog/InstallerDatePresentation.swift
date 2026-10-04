import Foundation

/// Read-only date presentation shared by collection cells, sorting and details.
/// A receipt describes historical installer activity, never original addition or use.
public struct InstallerDatePresentation: Sendable {
    public let date: Date?
    public let value: String
    public let detail: String
    public let accessibility: String
}

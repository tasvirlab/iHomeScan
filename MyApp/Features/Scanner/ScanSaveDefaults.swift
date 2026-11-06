import Foundation

enum ScanSaveDefaults {
    static func nextRoomName(
        existingNames: [String],
        localizedName: (Int) -> String
    ) -> String {
        let used = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var index = 1
        while used.contains(localizedName(index).lowercased()) { index += 1 }
        return localizedName(index)
    }
}

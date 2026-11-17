import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@Suite("Precision editor UX")
struct PrecisionEditorUXTests {
    private let horizontalID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let diagonalID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    @Test("Wall tap selects a horizontal wall within a comfortable tolerance")
    func horizontalSelection() {
        let targets = [PrecisionWallHitTarget(wallID: horizontalID, start: .init(x: 20, y: 80), end: .init(x: 220, y: 80))]
        #expect(PrecisionWallHitTesting.selectedWall(at: .init(x: 100, y: 96), targets: targets) == horizontalID)
    }

    @Test("Diagonal and short walls remain selectable")
    func diagonalAndShortSelection() {
        let targets = [PrecisionWallHitTarget(wallID: diagonalID, start: .init(x: 40, y: 40), end: .init(x: 62, y: 62))]
        #expect(PrecisionWallHitTesting.selectedWall(at: .init(x: 52, y: 49), targets: targets) == diagonalID)
    }

    @Test("Tapping empty canvas deselects")
    func emptySelection() {
        let targets = [PrecisionWallHitTarget(wallID: horizontalID, start: .zero, end: .init(x: 40, y: 0))]
        #expect(PrecisionWallHitTesting.selectedWall(at: .init(x: 100, y: 100), targets: targets) == nil)
    }

    @Test("Overlapping hit targets resolve deterministically")
    func deterministicSelection() {
        let later = PrecisionWallHitTarget(wallID: diagonalID, start: .zero, end: .init(x: 100, y: 0))
        let earlier = PrecisionWallHitTarget(wallID: horizontalID, start: .zero, end: .init(x: 100, y: 0))
        #expect(PrecisionWallHitTesting.selectedWall(at: .init(x: 50, y: 2), targets: [later, earlier]) == horizontalID)
    }

    @Test("Uzbek, English and Russian decimal separators parse into meters")
    func localeDecimalInput() throws {
        for language in [AppLanguage.uzbek, .english, .russian] {
            let suite = "PrecisionEditorUXTests.\(language.rawValue)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.set(language.rawValue, forKey: "settings.language")
            defaults.set(MeasurementUnit.meters.rawValue, forKey: "settings.units")
            let settings = AppSettings(defaults: defaults)
            #expect(try settings.parseLength("4,25").get() == 4.25)
            #expect(try settings.parseLength("4.25").get() == 4.25)
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

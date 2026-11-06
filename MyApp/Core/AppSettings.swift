import SwiftUI
import Observation

/// Languages the app ships with. The user can switch language inside the app,
/// independently of the system language (matching the prototype's language pill).
enum AppLanguage: String, CaseIterable, Identifiable {
    case uzbek = "uz"
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Endonym shown in pickers — intentionally not translated.
    var displayName: String {
        switch self {
        case .uzbek: "Oʻzbekcha"
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// Short code displayed in the header language pill.
    var code: String { rawValue.uppercased() }

    /// Locale used for number and date formatting.
    var locale: Locale {
        switch self {
        case .uzbek: Locale(identifier: "uz_Latn_UZ")
        case .english: Locale(identifier: "en_US")
        case .russian: Locale(identifier: "ru_RU")
        }
    }

    /// Picks the best supported language from the device's preferred languages.
    static var deviceDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if let match = AppLanguage(rawValue: code ?? "") { return match }
        }
        return .english
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var titleKey: String { "appearance.\(rawValue)" }
}

enum MeasurementUnit: String, CaseIterable, Identifiable {
    case millimeters = "mm"
    case meters = "m"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .millimeters: "units.millimeters"
        case .meters: "units.meters"
        }
    }
}

/// User preferences persisted in `UserDefaults`, plus localization and formatting helpers
/// that respect the in-app language choice.
@Observable
final class AppSettings {
    private enum Keys {
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let units = "settings.units"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            bundle = Self.bundle(for: language)
        }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var units: MeasurementUnit {
        didSet { defaults.set(units.rawValue, forKey: Keys.units) }
    }

    /// The `.lproj` bundle for the selected language; strings are looked up here.
    private var bundle: Bundle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .deviceDefault
        self.language = language
        self.appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init) ?? .system
        self.units = defaults.string(forKey: Keys.units).flatMap(MeasurementUnit.init) ?? .millimeters
        self.bundle = Self.bundle(for: language)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    var locale: Locale { language.locale }

    // MARK: - Localization

    /// Returns the localized string for `key` in the selected app language.
    func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Returns the localized format string for `key`, filled with `arguments`.
    /// Plural variations from the String Catalog are resolved for the selected language.
    func t(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }

    func roomCount(_ count: Int) -> String {
        t("rooms.count", count)
    }

    // MARK: - Formatting

    /// Area in square meters, e.g. "59.3 m²" / "59,3 м²".
    func area(_ squareMeters: Double) -> String {
        let number = squareMeters.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return "\(number) \(t("unit.sqm"))"
    }

    /// A length (stored in meters) without a unit, in the selected display unit:
    /// grouped whole millimeters or meters with two decimals.
    func lengthValue(_ meters: Double) -> String {
        switch units {
        case .millimeters:
            Int((meters * 1000).rounded()).formatted(.number.grouping(.automatic).locale(locale))
        case .meters:
            meters.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }
    }

    var lengthUnitSymbol: String {
        t(units == .millimeters ? "unit.mm" : "unit.m")
    }

    /// A length with its unit, e.g. "4,200 mm" / "4,20 m".
    func length(_ meters: Double) -> String {
        "\(lengthValue(meters)) \(lengthUnitSymbol)"
    }

    /// Room dimensions, e.g. "4,200 × 4,800 mm". Unknown sides are shown as "—".
    func dimensions(width: Double?, length: Double?) -> String? {
        guard width != nil || length != nil else { return nil }
        let w = width.map(lengthValue) ?? "—"
        let l = length.map(lengthValue) ?? "—"
        return "\(w) × \(l) \(lengthUnitSymbol)"
    }

    /// Ceiling height is always shown in meters with one decimal, as in the design.
    func ceilingHeight(_ meters: Double) -> String {
        let number = meters.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return "\(number) \(t("unit.m"))"
    }

    // MARK: - Input

    /// Text for editing a stored length in the selected unit (no grouping separators).
    func editableLength(_ meters: Double?) -> String {
        guard let meters else { return "" }
        switch units {
        case .millimeters:
            return String(Int((meters * 1000).rounded()))
        case .meters:
            return meters.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))
        }
    }

    func editableArea(_ squareMeters: Double?) -> String {
        guard let squareMeters else { return "" }
        return squareMeters.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    /// Parses a user-entered length in the selected unit and returns meters.
    /// Empty input → `.success(nil)`; unparsable or non-positive input → `.failure`.
    func parseLength(_ text: String) -> Result<Double?, RepositoryError> {
        parseNumber(text).map { value in
            value.map { units == .millimeters ? $0 / 1000 : $0 }
        }
    }

    /// Parses a user-entered area in square meters.
    func parseArea(_ text: String) -> Result<Double?, RepositoryError> {
        parseNumber(text)
    }

    /// Accepts both "," and "." as the decimal separator and ignores spaces.
    private func parseNumber(_ text: String) -> Result<Double?, RepositoryError> {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return .success(nil) }
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return .failure(.invalidMeasurement) }
        return .success(value)
    }

    /// Display name for a floor: the user's name, or the localized default ("1-qavat", "Floor 1", "Этаж 1").
    func floorName(_ floor: Floor) -> String {
        floor.name.nilIfBlank ?? t("floor.defaultName", floor.level)
    }

    /// "Today" for the current day, otherwise a short day + month.
    func shortDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return t("date.today") }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}

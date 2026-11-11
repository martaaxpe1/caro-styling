import Foundation

/// What Caro works out from a country (screen 02): its name, currency, date order, size system
/// and temperature unit, and the words used on screen 04 ("US site", "in the US").
/// It uses the iPhone's own knowledge of countries (Locale), so nothing is typed in by hand
/// apart from a few words.
enum PlaceFormats {
    private static let english = Locale(identifier: "en")

    /// The iPhone's settings for English as written in a country, like en_US or en_NL.
    private static func locale(_ country: String) -> Locale {
        Locale(identifier: "en_\(country)")
    }

    /// "United States"
    static func countryName(_ country: String) -> String {
        english.localizedString(forRegionCode: country) ?? country
    }

    static func defaultCurrency(_ country: String) -> String {
        locale(country).currency?.identifier ?? "EUR"
    }

    /// "US dollar", in sentence case.
    static func currencyName(_ code: String) -> String {
        let name = english.localizedString(forCurrencyCode: code) ?? code
        let words = name.split(separator: " ").enumerated().map { index, word in
            // Keep the first word, and short forms like US, as they are.
            index == 0 || word == word.uppercased() ? String(word) : word.lowercased()
        }
        return words.joined(separator: " ")
    }

    /// Currencies to choose from in Change, by name.
    static var allCurrencies: [String] {
        Locale.commonISOCurrencyCodes.sorted { currencyName($0) < currencyName($1) }
    }

    /// Oct 30 in the US, 30 Oct in the Netherlands.
    static func defaultDateOrder(_ country: String) -> DateOrder {
        let pattern = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: locale(country)) ?? "d MMM"
        return pattern.hasPrefix("d") ? .dayMonth : .monthDay
    }

    static func defaultSizeSystem(_ country: String) -> SizeSystem {
        switch country {
        case "US", "CA": .us
        case "GB", "IE": .uk
        case "AU", "NZ": .au
        default: .eu
        }
    }

    /// A date as the member's dates look: "Oct 30" or "30 Oct".
    static func shortDate(_ date: Date, order: DateOrder) -> String {
        let formatter = DateFormatter()
        formatter.locale = english
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = order == .monthDay ? "MMM d" : "d MMM"
        return formatter.string(from: date)
    }

    /// The server's dates, like 2026-10-30, as a day.
    static func day(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: text)
    }

    /// The month of a server date: 10 for 2026-10-30.
    static func month(_ text: String) -> Int? {
        let parts = text.split(separator: "-")
        return parts.count == 3 ? Int(parts[1]) : nil
    }

    /// True where the typical highs read in °F, like the US.
    static func usesFahrenheit(_ country: String) -> Bool {
        locale(country).measurementSystem == .us
    }

    /// A choice with the country's own formats, before the member changes any.
    static func defaults(for city: City) -> PlaceChoice {
        PlaceChoice(
            city: city,
            currency: defaultCurrency(city.country),
            dateOrder: defaultDateOrder(city.country),
            sizeSystem: defaultSizeSystem(city.country)
        )
    }

    // MARK: Words for stores (screen 04)

    /// "the US", "the Netherlands", "Chile"
    static func countryInSentence(_ country: String) -> String {
        switch country {
        case "US": "the US"
        case "GB": "the UK"
        case "NL", "PH", "AE", "DO", "BS", "GM": "the \(countryName(country))"
        default: countryName(country)
        }
    }

    private static let siteAdjectives = [
        "US": "US", "GB": "UK", "NL": "Dutch", "BE": "Belgian", "DE": "German", "FR": "French",
        "ES": "Spanish", "IT": "Italian", "PT": "Portuguese", "IE": "Irish", "AT": "Austrian",
        "CH": "Swiss", "DK": "Danish", "SE": "Swedish", "NO": "Norwegian", "FI": "Finnish",
        "PL": "Polish", "CA": "Canadian", "AU": "Australian", "MX": "Mexican", "BR": "Brazilian",
        "AR": "Argentinian", "JP": "Japanese",
    ]

    /// "US site", or "site for Chile". `plural` gives "US sites".
    static func site(_ country: String, plural: Bool = false) -> String {
        let noun = plural ? "sites" : "site"
        if let adjective = siteAdjectives[country] {
            return "\(adjective) \(noun)"
        }
        return "\(noun) for \(countryInSentence(country))"
    }
}

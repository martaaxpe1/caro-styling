import Foundation

// A member's set-up, as the server sends it: the answers from onboarding steps 1 to 5,
// which Settings changes later. From GET /me/setup and every save.

struct Setup: Decodable {
    let member: Member
    /// Who sent the invitation, like "Marta". Empty for the admin.
    let invitedBy: String?
    /// Where you live. Empty until step 2 is saved.
    let place: Place?
    /// True once the year (step 3) was saved, even as no seasons.
    let yearConfirmed: Bool
    let seasons: [Season]
    let sections: Sections
    let stores: [Store]
    /// The server's today, like 2026-10-30. DEV_TODAY changes it while testing.
    let today: String
}

/// Where the member lives, and how dates, prices and sizes look for them.
struct Place: Decodable, Equatable {
    /// The city's number in the city search. Empty for members set up before T4.
    let cityId: Int?
    let city: String
    let region: String?
    /// Two letters, like US.
    let country: String
    let currency: String?
    let dateOrder: DateOrder?
    let sizeSystem: SizeSystem?
}

/// 30 Oct or Oct 30.
enum DateOrder: String, Codable, CaseIterable, Hashable {
    case dayMonth = "day month"
    case monthDay = "month day"
}

enum SizeSystem: String, Codable, CaseIterable, Hashable {
    case eu = "EU", us = "US", uk = "UK", au = "AU"

    /// "US (4, 6, 8)", as on screen 02.
    var example: String {
        switch self {
        case .eu: "EU (36, 38, 40)"
        case .us: "US (4, 6, 8)"
        case .uk: "UK (8, 10, 12)"
        case .au: "AU (8, 10, 12)"
        }
    }
}

/// A city from the city search: Miami, Florida, US.
struct City: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let region: String?
    let country: String

    /// "Miami, Florida, United States"
    var label: String {
        [name, region, PlaceFormats.countryName(country)].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A city with the formats the member confirmed, waiting to be saved.
struct PlaceChoice: Hashable {
    let city: City
    var currency: String
    var dateOrder: DateOrder
    var sizeSystem: SizeSystem
}

/// One season: its name and its months, 1 is January.
struct Season: Codable, Equatable, Hashable {
    var name: String
    var months: [Int]
}

/// The store sections a member shops in. What they shop for, not who they are.
struct Sections: Codable, Equatable {
    var womens: Bool
    var mens: Bool
    var unisex: Bool

    var any: Bool { womens || mens || unisex }

    /// "women's, unisex"
    var words: String {
        [womens ? "women's" : nil, mens ? "men's" : nil, unisex ? "unisex" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// One of the member's stores.
struct Store: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let domain: String?
    let countryUrl: String?
    let sellsOnline: Bool
    /// The country its website was found for.
    let country: String?
}

/// What Caro found for a store name, shown on the card in step 4 before it is added.
struct FoundStore: Codable, Equatable {
    let found: Bool
    let name: String
    var domain: String?
    var countryUrl: String?
    var sellsOnline: Bool?
    var country: String?
}

/// GET /me/year: a city's typical weather and the years the rule proposes.
struct YearProposal: Decodable {
    let city: City
    let months: [MonthWeather]
    let suggested: SeasonCount
    let options: Options
    /// The year the member already confirmed for this city, if any.
    let saved: [Season]?
    let today: String

    struct Options: Decodable {
        let four: [Season]
        let two: [Season]
        let none: [Season]
    }

    func seasons(for count: SeasonCount) -> [Season] {
        switch count {
        case .four: options.four
        case .two: options.two
        case .none: options.none
        }
    }
}

struct MonthWeather: Decodable {
    let month: Int
    let highC: Double
    let rainMm: Double
}

enum SeasonCount: String, Decodable, CaseIterable {
    case four, two, none

    init(count: Int) {
        self = count == 4 ? .four : count == 2 ? .two : .none
    }

    var label: String {
        switch self {
        case .four: "Four seasons"
        case .two: "Two seasons"
        case .none: "No seasons"
        }
    }
}

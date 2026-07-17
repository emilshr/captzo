import Foundation

extension Date {
    func scratioSidebarLabel(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = L10n.currentLocale
    ) -> String {
        var calendar = calendar
        calendar.locale = locale

        let time = formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))

        if calendar.isDateInToday(self) {
            return String(localized: "Today, \(time)", locale: locale)
        }

        if calendar.isDateInYesterday(self) {
            return String(localized: "Yesterday, \(time)", locale: locale)
        }

        if calendar.isDate(self, equalTo: referenceDate, toGranularity: .weekOfYear) {
            let weekday = formatted(Date.FormatStyle().locale(locale).weekday(.wide))
            return String(localized: "\(weekday), \(time)", locale: locale)
        }

        return formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }
}

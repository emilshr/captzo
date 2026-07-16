import Foundation

extension Date {
    func scratioSidebarLabel(referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let time = formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(self) {
            return "Today, \(time)"
        }

        if calendar.isDateInYesterday(self) {
            return "Yesterday, \(time)"
        }

        if calendar.isDate(self, equalTo: referenceDate, toGranularity: .weekOfYear) {
            let weekday = formatted(.dateTime.weekday(.wide))
            return "\(weekday), \(time)"
        }

        return formatted(date: .abbreviated, time: .shortened)
    }
}

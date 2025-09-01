import Foundation

struct Conference: Identifiable, Hashable {
    let id: String
    let summary: String
    let startDate: Date
    let endDate: Date
    let descriptionText: String?
    let location: String?
    let url: URL?
    // Conference is a data model; fetching and timer logic should be handled elsewhere.
}

class CalendarService: ObservableObject {
    @Published var conferences = [Conference]()
    private var timer: Timer?

    init() {
        fetchAndParseICS()
        // Start a timer to fetch data every hour
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.fetchAndParseICS()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func fetchAndParseICS() {
        guard let url = URL(string: "https://ccfddl.com/conference/deadlines_en.ics") else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Failed to fetch ICS file: \(error.localizedDescription)")
                return
            }

            guard let data = data, let icsString = String(data: data, encoding: .utf8) else {
                print("No data or failed to decode data")
                return
            }

            let parsedConferences = self.parseICS(icsString: icsString)
            
            DispatchQueue.main.async {
                let currentDate = Date()
                self.conferences = parsedConferences
                    .filter { $0.endDate > currentDate } // 排除已经过期的会议
                    .sorted(by: { $0.summary < $1.summary }) // 按会议名称字母序排序
            }
        }.resume()
    }

    private func parseICS(icsString: String) -> [Conference] {
        var conferences = [Conference]()
        let lines = icsString.components(separatedBy: .newlines)
        
        var currentEventProperties = [String: String]()
        var inEvent = false
        var lastKey: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine == "BEGIN:VEVENT" {
                inEvent = true
                currentEventProperties = [:]
                lastKey = nil
            } else if trimmedLine == "END:VEVENT" {
                inEvent = false
                if let conference = createConference(from: currentEventProperties) {
                    // print(conference)
                    conferences.append(conference)
                }
                lastKey = nil
            } else if inEvent {
                if trimmedLine.starts(with: " ") {
                    // Handle property value continuation (indented lines)
                    if let key = lastKey {
                        currentEventProperties[key]? += trimmedLine.trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    // Parse property line
                    let (key, value) = parsePropertyLine(trimmedLine)
                    if !key.isEmpty {
                        lastKey = key
                        currentEventProperties[key] = value
                    }
                }
            }
        }
        
        return conferences
    }
    
    private func parsePropertyLine(_ line: String) -> (key: String, value: String) {
        // For lines like DTEND;TZID="UTC-12:00":20210910T000059
        // We need to find the last colon followed by a datetime pattern
        
        // Look for datetime pattern at the end of the line
        let dateTimePattern = #"\d{8}T\d{6}(\d{2})?$"#
        if let dateTimeRange = line.range(of: dateTimePattern, options: .regularExpression) {
            let dateTimeValue = String(line[dateTimeRange])
            let keyPart = String(line[..<dateTimeRange.lowerBound])
            
            // Remove trailing colon from key part
            let cleanKey = keyPart.hasSuffix(":") ? String(keyPart.dropLast()) : keyPart
            return (cleanKey, dateTimeValue)
        }
        
        // Standard parsing for normal key:value pairs
        let parts = line.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        
        return ("", "")
    }

    private func createConference(from properties: [String: String]) -> Conference? {
        guard let uid = properties["UID"],
              let summary = properties["SUMMARY"] else {
            return nil
        }

        // Find DTSTART and DTEND properties, which may include TZID
        let dtstartKey = properties.keys.first { $0.hasPrefix("DTSTART") }
        let dtendKey = properties.keys.first { $0.hasPrefix("DTEND") }

        guard let startKey = dtstartKey, let endKey = dtendKey,
              let dtstartStr = properties[startKey],
              let dtendStr = properties[endKey] else {
            return nil
        }

        let startTzid = extractTzid(from: startKey)
        let endTzid = extractTzid(from: endKey)

        let startDate = parseDate(from: dtstartStr, tzid: startTzid) ?? Date()
        let endDate = parseDate(from: dtendStr, tzid: endTzid) ?? Date()

        // print(summary, endDate)
        
        let description = properties["DESCRIPTION"]?.replacingOccurrences(of: "\n", with: "\n")
        let location = properties["LOCATION"]
        let url = URL(string: properties["URL"] ?? "")

        return Conference(
            id: uid,
            summary: summary,
            startDate: startDate,
            endDate: endDate,
            descriptionText: description,
            location: location,
            url: url
        )
    }

    // 返回的是时区ID UTC-12
    private func extractTzid(from key: String) -> String? {
        let components = key.split(separator: ";")
        for component in components {
            if component.hasPrefix("TZID=") {
                let tzidWithQuotes = String(component.dropFirst(5))
                // Remove quotes if they exist
                return tzidWithQuotes.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    private func parseDate(from dateString: String, tzid: String?) -> Date? {
        let dateFormatter = DateFormatter()
        let cleanDateString = dateString.trimmingCharacters(in: .whitespaces)

        // Case 1: Date is in UTC format (ends with 'Z')
        if cleanDateString.hasSuffix("Z") {
            dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
            // print(cleanDateString, dateFormatter.date(from: cleanDateString))
            return dateFormatter.date(from: cleanDateString)
        }

        // Case 2: Date has a TZID parameter
        if let tzid = tzid {
            if let timeZone = TimeZone(identifier: tzid) {
                dateFormatter.timeZone = timeZone
            } else if let offset = parseTimeZoneOffset(from: tzid) {
                dateFormatter.timeZone = TimeZone(secondsFromGMT: offset)
            } else {
                // Fallback for an unknown TZID
                dateFormatter.timeZone = TimeZone.current
            }
            dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
            return dateFormatter.date(from: cleanDateString)
        }
        
        // Case 3: Floating date/time (no 'Z' and no TZID)
        // Interpret as local time
        dateFormatter.timeZone = TimeZone.current
        if cleanDateString.count == 8 && !cleanDateString.contains("T") {
            // Format is yyyyMMdd (Date only)
            dateFormatter.dateFormat = "yyyyMMdd"
        } else {
            // Format is yyyyMMdd'T'HHmmss (Date with time)
            dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return dateFormatter.date(from: cleanDateString)
    }
    
    private func parseTimeZoneOffset(from tzid: String) -> Int? {
        // This regex handles formats like "UTC-12:00" or "UTC+08:00"
        let pattern = #"UTC([+-])(\d{1,2}):(\d{2})"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: tzid, options: [], range: NSRange(location: 0, length: tzid.utf16.count)) {
                let signRange = Range(match.range(at: 1), in: tzid)!
                let hourRange = Range(match.range(at: 2), in: tzid)!
                let minuteRange = Range(match.range(at: 3), in: tzid)!
                
                let sign = String(tzid[signRange])
                let hours = Int(tzid[hourRange]) ?? 0
                let minutes = Int(tzid[minuteRange]) ?? 0
                
                let totalSeconds = (hours * 3600) + (minutes * 60)
                return sign == "+" ? totalSeconds : -totalSeconds
            }
        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }
}

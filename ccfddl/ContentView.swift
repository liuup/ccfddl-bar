//
//  ContentView.swift
//  ccfddl
//
//  Created by UP on 8/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var calendarService = CalendarService()

    var body: some View {
        NavigationView {
            List(calendarService.conferences) { conference in
                VStack(alignment: .leading) {
                    Text(conference.summary)
                        .font(.headline)
                    Text("From: \(conference.startDate, formatter: itemFormatter) To: \(conference.endDate, formatter: itemFormatter)")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Conference Deadlines")
            .onAppear {
                calendarService.fetchAndParseICS()
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter
}()

#Preview {
    ContentView()
}

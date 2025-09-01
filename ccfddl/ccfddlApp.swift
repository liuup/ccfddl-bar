//
//  ccfddlApp.swift
//  ccfddl
//
//  Created by UP on 8/21/25.
//

import SwiftUI

//class Clock: ObservableObject {
//    @Published var now = Date()
//    private var timer: Timer?
//
//    init() {
//        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//            self.now = Date()
//        }
//    }
//}


let sharedCalendarService = CalendarService()

@main
struct MyMenuBarApp: App {
    @StateObject private var calendarService = sharedCalendarService
    @State private var selectedConference: Conference?
    @State private var timer: Timer?
    @State private var countdownText: String = "Select"

    var body: some Scene {
        MenuBarExtra {
            
            
            // Divider()

            ForEach(calendarService.conferences) { conference in
                Button(action: {
                    selectedConference = conference
                    updateCountdown()
                }) {
                    HStack {
                        // 固定宽度的对勾区域，确保对齐
                        Group {
                            if selectedConference?.id == conference.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            } else {
                                // 空的占位符区域，不显示任何内容
                                Spacer()
                            }
                        }
                        .frame(width: 16) // 固定宽度
                        
                        Text(conference.summary)
                        Spacer()
                    }
                }
            }
            
            Divider()

            Button("Refresh") {
                calendarService.fetchAndParseICS()
            }
            
            // Button("Settings") { print("settings") }
            Button("Exit") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(countdownText)
                .monospacedDigit()
                .onAppear(perform: setupTimer)
                .onChange(of: selectedConference) { _ in updateCountdown() }
        }
    }

    private func setupTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateCountdown()
        }
    }

    private func updateCountdown() {
        guard let conference = selectedConference else {
            countdownText = "Select"
            return
        }

        let now = Date()
        let targetDate = conference.endDate
        
        // print(now)
        // print("target", targetDate)
        
        if now > targetDate {
            countdownText = "Conf ended"
            return
        }

        let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: now, to: targetDate)
        
        let days = components.day ?? 0
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0

        countdownText = String(format: "%02dd %02dh", days, hours)
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import CoreData
@testable import Pulse

final class LoggerStoreSessionTests: XCTestCase {
    private var storeURL: URL!
    private let previousSession = LoggerStore.Session(startDate: Date().addingTimeInterval(-3600))

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggerStoreSessionTests-\(UUID().uuidString)", isDirectory: true)

        // Simulate a previous launch that left a session with one message behind.
        var configuration = LoggerStore.Configuration()
        configuration.isAutoStartingSession = false
        let store = try LoggerStore(storeURL: storeURL, options: [.create, .synchronous], configuration: configuration)
        store.startSession(previousSession, info: .current)
        store.storeMessage(label: "test", level: .debug, message: "previous launch")
        try store.close()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL)
    }

    func testAutoStartedSessionIsNotReplacedByPreviousSession() throws {
        // Default (asynchronous) options, like the shared store on a cold launch.
        let store = try LoggerStore(storeURL: storeURL, options: [.create])
        store.storeMessage(label: "test", level: .debug, message: "this launch")

        XCTAssertEqual(store.session.id, LoggerStore.Session.current.id)

        let context = store.backgroundContext
        try context.performAndWait {
            try context.save()

            let sessions = try context.fetch(NSFetchRequest<LoggerSessionEntity>(entityName: "LoggerSessionEntity"))
            XCTAssertEqual(Set(sessions.map(\.id)), [previousSession.id, LoggerStore.Session.current.id])

            let messages = try context.fetch(NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity"))
            let sessionsByMessage = Dictionary(uniqueKeysWithValues: messages.map { ($0.text, $0.session) })
            XCTAssertEqual(sessionsByMessage, [
                "previous launch": previousSession.id,
                "this launch": LoggerStore.Session.current.id
            ])
        }
    }

    func testReadonlyStoreAdoptsLatestSession() throws {
        let store = try LoggerStore(storeURL: storeURL, options: [.readonly])

        XCTAssertEqual(store.session.id, previousSession.id)
    }
}

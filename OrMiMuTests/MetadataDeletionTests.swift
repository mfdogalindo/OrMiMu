//
//  MetadataDeletionTests.swift
//  OrMiMuTests
//
//  Created by Jules on 2/07/24.
//

import XCTest
import SwiftData
@testable import OrMiMu

final class MetadataDeletionTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUpWithError() throws {
        let schema = Schema([SongItem.self, PlaylistItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    @MainActor
    func testRefreshMetadataDeletesMissingFile() async throws {
        // Arrange
        let fakePath = "/tmp/non_existent_file_\(UUID().uuidString).mp3"
        let song = SongItem(
            title: "Test Title",
            artist: "Test Artist",
            album: "Test Album",
            genre: "Test Genre",
            year: "2024",
            filePath: fakePath,
            duration: 120
        )

        modelContext.insert(song)
        try modelContext.save()

        // Verify insertion worked
        var descriptor = FetchDescriptor<SongItem>()
        var initialSongs = try modelContext.fetch(descriptor)
        XCTAssertEqual(initialSongs.count, 1, "Song should be initially inserted")

        // Initialize Service
        // LibraryService uses modelContext passed in init
        let service = LibraryService(modelContext: modelContext)

        // Act
        // Pass the song to refreshMetadata
        // Note: refreshMetadata takes [SongItem], so we pass the one we just inserted.
        // Even if we passed [] it might not work if it relied on fetching, but it takes an array.
        await service.refreshMetadata(for: [song])

        // Assert
        // The song should be deleted because the file does not exist at fakePath
        // We need to fetch again to see current state
        descriptor = FetchDescriptor<SongItem>()
        let finalSongs = try modelContext.fetch(descriptor)

        // EXPECTED FAILURE: Currently the code does NOT delete the song.
        // So I expect this assertion to fail until I fix the code.
        XCTAssertEqual(finalSongs.count, 0, "Song should be deleted from context because file is missing")
    }
}

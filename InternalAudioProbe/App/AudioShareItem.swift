import AudioCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct AudioShareItem: Transferable, Sendable {
    let url: URL
    let filename: String

    init(url: URL, startedAt: Date, index: Int = 0) {
        self.url = url
        filename = RecordingName.audioFile(startedAt: startedAt, index: index)
    }

    static var transferRepresentation: some TransferRepresentation {
        // File transfers avoid loading long recordings into Data or creating a persistent export copy.
        // https://developer.apple.com/documentation/coretransferable/filerepresentation
        FileRepresentation(exportedContentType: .mpeg4Audio) { item in
            SentTransferredFile(item.url)
        }
        .exportingCondition { $0.url.isFileURL && $0.url.pathExtension.lowercased() == "m4a" }
        // Gives legacy recording.m4a files a date-based export name without modifying the original.
        // https://developer.apple.com/documentation/coretransferable/transferrepresentation/suggestedfilename(_:)-47rg0
        .suggestedFileName { $0.filename }
    }
}

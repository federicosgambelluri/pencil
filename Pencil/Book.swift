import Foundation
import SwiftData

// MARK: - Stato di lettura
enum ReadingStatus: String, Codable, CaseIterable {
    case toRead   = "Da Leggere"
    case reading  = "In Lettura"
    case read     = "Letto"
    
    var icon: String {
        switch self {
        case .toRead:  return "bookmark"
        case .reading: return "book.fill"
        case .read:    return "checkmark.circle.fill"
        }
    }
    
    var color: String {   // usato per codificare il Color in SwiftUI
        switch self {
        case .toRead:  return "blue"
        case .reading: return "orange"
        case .read:    return "green"
        }
    }
    
    var gradientColors: [String] {
        switch self {
        case .toRead:  return ["#3B82F6", "#6366F1"]   // blue→indigo
        case .reading: return ["#F59E0B", "#EF4444"]   // amber→red
        case .read:    return ["#10B981", "#059669"]   // emerald
        }
    }
}

// MARK: - Modello Book
@Model
final class Book {
    // ─── Campi originali ───────────────────────────────────────────────
    var title: String
    var author: String
    var format: String
    var fileName: String?
    var kindleFileName: String?
    var dateAdded: Date
    var dateModified: Date
    @Attribute(.externalStorage) var coverImageData: Data?

    // ─── Lettura ────────────────────────────────────────────────────────
    var readingStatusRaw: String = ReadingStatus.toRead.rawValue
    var readingProgress: Double  = 0.0     // 0.0 … 1.0
    var startedDate: Date?       = nil
    var finishedDate: Date?      = nil

    // ─── Organizzazione ─────────────────────────────────────────────────
    var tags: [String]   = []
    var rating: Int      = 0               // 0…5 stelle

    // ─── Proprietà computate: stato lettura ─────────────────────────────
    var readingStatus: ReadingStatus {
        get { ReadingStatus(rawValue: readingStatusRaw) ?? .toRead }
        set { readingStatusRaw = newValue.rawValue }
    }

    // ─── Proprietà computate: sorgente ──────────────────────────────────
    var isLocalOnly:  Bool { fileName != nil && kindleFileName == nil }
    var isKindleOnly: Bool { fileName == nil && kindleFileName != nil }
    var isSynced:     Bool { fileName != nil && kindleFileName != nil }

    // ─── Inizializzatore ────────────────────────────────────────────────
    init(title: String,
         author: String,
         format: String,
         fileName: String?      = nil,
         kindleFileName: String? = nil,
         dateAdded: Date        = Date(),
         dateModified: Date     = Date(),
         coverImageData: Data?  = nil,
         readingStatus: ReadingStatus = .toRead,
         readingProgress: Double = 0.0,
         tags: [String]         = [],
         rating: Int            = 0) {
        self.title            = title
        self.author           = author
        self.format           = format
        self.fileName         = fileName
        self.kindleFileName   = kindleFileName
        self.dateAdded        = dateAdded
        self.dateModified     = dateModified
        self.coverImageData   = coverImageData
        self.readingStatusRaw = readingStatus.rawValue
        self.readingProgress  = readingProgress
        self.tags             = tags
        self.rating           = rating
    }
}

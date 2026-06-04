import SwiftUI
import SwiftData

@main
struct PencilApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Book.self])
        
        // URL fisso per il database: evita che SwiftData usi posizioni diverse
        // a seconda di come viene lanciata l'app (da Xcode vs. bundle finale)
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport
            .appendingPathComponent("PencilApp")
            .appendingPathComponent("Library.sqlite")
        
        // Crea la cartella se non esiste
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // ModelConfiguration con migrazione automatica leggera abilitata:
        // "cloudKitDatabase: .none" evita errori se iCloud non è configurato.
        // Quando lo schema cambia (nuovo campo, rinomina…), SwiftData
        // esegue una lightweight migration invece di cancellare tutto.
        let config = ModelConfiguration(
            "PencilLibrary",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Se la migrazione fallisce (schema incompatibile),
            // proviamo a recuperare facendo un backup e ricreando il DB.
            print("⚠️ SwiftData migration error: \(error)")
            print("⚠️ Tentativo di recupero: backup del database corrotto...")
            
            let backupURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("Library_backup_\(Int(Date().timeIntervalSince1970)).sqlite")
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
            try? FileManager.default.removeItem(at: storeURL)
            
            // Prova di nuovo con un database pulito
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Impossibile creare il ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear { scheduleWeeklyBackupIfNeeded() }
        }
        .modelContainer(sharedModelContainer)
        
        Settings {
            SettingsView()
        }
    }
    
    // Esegue un backup automatico se non ne è stato fatto uno negli ultimi 7 giorni
    private func scheduleWeeklyBackupIfNeeded() {
        let key = "lastBackupDate"
        let lastBackup = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        let daysSinceLast = Calendar.current.dateComponents([.day], from: lastBackup, to: Date()).day ?? 8
        
        guard daysSinceLast >= 7 else {
            print("ℹ️ Backup già eseguito \(daysSinceLast) giorni fa — nessun backup necessario")
            return
        }
        
        // Esegui in background per non rallentare l'avvio
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) {
            BookImporter.performBackup()
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date(), forKey: key)
            }
        }
    }
}

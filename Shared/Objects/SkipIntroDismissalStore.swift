import Foundation

enum SkipIntroDismissalStore {
    private static let itemIDsKey = "EmbyLibMPVPlayer.skipIntroDismissedItemIDs"
    private static let generationByItemIDKey = "EmbyLibMPVPlayer.skipIntroGenerationByItemID"
    private static let scopeByItemIDKey = "EmbyLibMPVPlayer.skipIntroScopeByItemID"
    private static let generationByScopeIDKey = "EmbyLibMPVPlayer.skipIntroGenerationByScopeID"
    private static let secondsByScopeKey = "EmbyLibMPVPlayer.skipIntroSecondsByScope"

    static func contains(item: BaseItemDto?) -> Bool {
        guard let itemID = item?.id, itemIDs().contains(itemID) else { return false }
        let dismissedGeneration = generationByItemID()[itemID] ?? 0
        let storedScopeID = scopeByItemID()[itemID]
        let currentGeneration = storedScopeID
            .map { generation(forScopeID: $0) }
            ?? generation(for: item)
        return dismissedGeneration == currentGeneration
    }

    static func contains(itemID: String?) -> Bool {
        guard let itemID else { return false }
        return itemIDs().contains(itemID)
    }

    static func setDismissed(_ dismissed: Bool, item: BaseItemDto?) {
        guard let itemID = item?.id else { return }
        setDismissed(dismissed, itemID: itemID)

        var currentGenerationByItemID = generationByItemID()
        var currentScopeByItemID = scopeByItemID()
        if dismissed {
            currentGenerationByItemID[itemID] = generation(for: item)
            currentScopeByItemID[itemID] = scopeID(for: item)
        } else {
            currentGenerationByItemID.removeValue(forKey: itemID)
            currentScopeByItemID.removeValue(forKey: itemID)
        }
        UserDefaults.standard.set(currentGenerationByItemID, forKey: generationByItemIDKey)
        UserDefaults.standard.set(currentScopeByItemID, forKey: scopeByItemIDKey)
    }

    static func setDismissed(_ dismissed: Bool, itemID: String?) {
        guard let itemID else { return }
        var currentItemIDs = itemIDs()
        if dismissed {
            currentItemIDs.insert(itemID)
        } else {
            currentItemIDs.remove(itemID)

            var currentGenerationByItemID = generationByItemID()
            currentGenerationByItemID.removeValue(forKey: itemID)
            UserDefaults.standard.set(currentGenerationByItemID, forKey: generationByItemIDKey)

            var currentScopeByItemID = scopeByItemID()
            currentScopeByItemID.removeValue(forKey: itemID)
            UserDefaults.standard.set(currentScopeByItemID, forKey: scopeByItemIDKey)
        }
        UserDefaults.standard.set(Array(currentItemIDs), forKey: itemIDsKey)
    }

    static func reset(for item: BaseItemDto?) {
        guard let scopeID = scopeID(for: item) else {
            setDismissed(false, itemID: item?.id)
            return
        }

        reset(scopeID: scopeID, itemID: item?.id)
    }

    static func reset(seasonID: String?) {
        guard let seasonID, !seasonID.isEmpty else { return }
        reset(scopeID: "season:\(seasonID)", itemID: nil)
    }

    private static func reset(scopeID: String, itemID: String?) {

        var currentGenerationByScopeID = generationByScopeID()
        currentGenerationByScopeID[scopeID] = (currentGenerationByScopeID[scopeID] ?? 0) + 1
        UserDefaults.standard.set(currentGenerationByScopeID, forKey: generationByScopeIDKey)

        if let itemID {
            setDismissed(false, itemID: itemID)
        }
    }

    static func seconds(for item: BaseItemDto?, default defaultSeconds: Int) -> Int {
        guard let scopeID = scopeID(for: item) else { return defaultSeconds }
        return secondsByScope()[scopeID] ?? defaultSeconds
    }

    static func setSeconds(_ seconds: Int, for item: BaseItemDto?) {
        guard let scopeID = scopeID(for: item) else { return }
        var currentSecondsByScope = secondsByScope()
        currentSecondsByScope[scopeID] = max(5, seconds)
        UserDefaults.standard.set(currentSecondsByScope, forKey: secondsByScopeKey)
    }

    private static func itemIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: itemIDsKey) ?? [])
    }

    private static func generationByItemID() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: generationByItemIDKey) as? [String: Int] ?? [:]
    }

    private static func generationByScopeID() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: generationByScopeIDKey) as? [String: Int] ?? [:]
    }

    private static func scopeByItemID() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: scopeByItemIDKey) as? [String: String] ?? [:]
    }

    private static func generation(for item: BaseItemDto?) -> Int {
        guard let scopeID = scopeID(for: item) else { return 0 }
        return generation(forScopeID: scopeID)
    }

    private static func generation(forScopeID scopeID: String) -> Int {
        generationByScopeID()[scopeID] ?? 0
    }

    private static func secondsByScope() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: secondsByScopeKey) as? [String: Int] ?? [:]
    }

    private static func scopeID(for item: BaseItemDto?) -> String? {
        guard let item else { return nil }
        if item.type == .season, let itemID = item.id, !itemID.isEmpty {
            return "season:\(itemID)"
        }
        if let seasonID = item.seasonID, !seasonID.isEmpty {
            return "season:\(seasonID)"
        }
        if let itemID = item.id, !itemID.isEmpty {
            return "item:\(itemID)"
        }
        return nil
    }
}

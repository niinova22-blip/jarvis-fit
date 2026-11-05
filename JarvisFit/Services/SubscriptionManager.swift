import Foundation
import StoreKit

/// StoreKit 2 subscriptions. Entitlements are verified by StoreKit (JWS signed by the App Store)
/// and cached on device, so premium features keep working offline; buying, restoring and
/// renewals need an internet connection.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let monthlyID = "com.niinova.jarvisfit.premium.monthly"
    static let yearlyID = "com.niinova.jarvisfit.premium.yearly"
    static let productIDs = [monthlyID, yearlyID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium = false
    @Published private(set) var loadError: String?
    @Published private(set) var purchaseInProgress = false

    /// Listens for renewals/refunds for the app's lifetime (the manager is never deallocated).
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadError = loaded.isEmpty ? "unavailable" : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID) && transaction.revocationDate == nil {
                if let expiration = transaction.expirationDate, expiration < Date() { continue }
                active = true
            }
        }
        isPremium = active
    }

    enum PurchaseOutcome { case success, cancelled, pending, failed(String) }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed("verification") }
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .failed("unknown")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refreshEntitlements()
        return isPremium
    }
}

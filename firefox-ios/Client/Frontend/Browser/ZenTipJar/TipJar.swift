// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import StoreKit

/// The tip jar: the only money in Ensō, and the only reason it asks for any.
///
/// The tips are consumables, so there is nothing to restore and nothing that
/// unlocks: everything in the browser works the same before and after. That is
/// deliberate — a paid tier would mean promising support for a fork that has
/// to keep chasing its upstream, and a tip does not.
///
/// Nothing here reports anything. Apple handles the transaction and tells us
/// only that one happened, which is all we want to know: the privacy notice
/// says there are no servers of ours, and a tip must not make that false.
@MainActor
final class TipJar: ObservableObject {
    enum State {
        case loading
        case ready([Product])
        /// The store could not be reached, or the products are not configured.
        case unavailable
    }

    enum Outcome: Equatable {
        case thanks
        /// Waiting on someone else to approve it, as with Ask to Buy.
        case pending
        case failed
    }

    /// These have to exist in App Store Connect as consumables, under exactly
    /// these identifiers, before any of them will load on a device.
    ///
    /// App Store Connect reserves an identifier permanently once it is used:
    /// deleting the product does not release it. `.modest` is here rather than
    /// `.small` because `.small` was spent and cannot be taken back. Treat
    /// anything added below as one-way.
    static let productIDs = [
        "app.enso.tip.modest",
        "app.enso.tip.medium",
        "app.enso.tip.large"
    ]

    @Published private(set) var state: State = .loading
    @Published private(set) var purchasing: Product.ID?
    @Published var outcome: Outcome?

    private var updates: Task<Void, Never>?

    init() {
        // A tip approved later — Ask to Buy, or an interrupted purchase —
        // arrives here rather than from `tip(_:)`, and still has to be
        // finished or StoreKit will keep offering it back.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.finish(update)
            }
        }
    }

    deinit {
        updates?.cancel()
    }

    func load() async {
        state = .loading
        do {
            let products = try await Product.products(for: Self.productIDs)
            state = products.isEmpty ? .unavailable : .ready(products.sorted { $0.price < $1.price })
        } catch {
            state = .unavailable
        }
    }

    func tip(_ product: Product) async {
        guard purchasing == nil else { return }
        purchasing = product.id
        defer { purchasing = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                await finish(verification)
            case .pending:
                outcome = .pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            outcome = .failed
        }
    }

    /// Consumables have to be finished either way, or StoreKit replays them on
    /// every launch. An unverified one is finished without being thanked for.
    private func finish(_ verification: VerificationResult<Transaction>) async {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
            outcome = .thanks
        case .unverified(let transaction, _):
            await transaction.finish()
            outcome = .failed
        }
    }
}

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import StoreKit
import SwiftUI

struct TipJarView: View {
    @StateObject private var jar = TipJar()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(ImageIdentifiers.homeHeaderLogoBall)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                Text("Ensō is free, and stays free")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("""
                    There is nothing to unlock here. Every part of the browser \
                    works the same whether or not you leave anything, and \
                    nothing about a tip is reported anywhere — Apple handles \
                    it, and tells us only that it happened.
                    """)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                content
                    .padding(.horizontal, 20)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
        }
        .task { await jar.load() }
        .alert(item: $jar.outcome) { outcome in outcome.alert }
    }

    @ViewBuilder
    private var content: some View {
        switch jar.state {
        case .loading:
            ProgressView()
                .padding(.top, 12)

        case .ready(let products):
            VStack(spacing: 10) {
                ForEach(products, id: \.id) { product in
                    tipButton(product)
                }
            }

        case .unavailable:
            VStack(spacing: 6) {
                Text("The App Store can't be reached right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await jar.load() }
                }
            }
            .padding(.top, 12)
        }
    }

    private func tipButton(_ product: Product) -> some View {
        Button {
            Task { await jar.tip(product) }
        } label: {
            HStack {
                Text(product.displayName)
                Spacer()
                if jar.purchasing == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(jar.purchasing != nil)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }
}

extension TipJar.Outcome: Identifiable {
    var id: Self { self }

    var alert: Alert {
        switch self {
        case .thanks:
            return Alert(title: Text("Thank you"),
                         message: Text("That genuinely helps. Nothing has changed in the browser, which is the point."),
                         dismissButton: .default(Text("OK")))
        case .pending:
            return Alert(title: Text("Waiting for approval"),
                         message: Text("The tip needs approving on another device first. Nothing has been charged yet."),
                         dismissButton: .default(Text("OK")))
        case .failed:
            return Alert(title: Text("That didn't go through"),
                         message: Text("Nothing was charged. It's worth trying again in a moment."),
                         dismissButton: .default(Text("OK")))
        }
    }
}

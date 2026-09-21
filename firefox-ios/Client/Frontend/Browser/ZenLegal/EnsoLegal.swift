// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

/// Ensō's own terms and privacy notice, served from the app rather than
/// fetched: pointing people at Mozilla's pages would be telling them the terms
/// of a different browser, made by a company this one has nothing to do with.
///
/// They ship as files so the documents someone agreed to are the ones in the
/// build they are running, and so they work with no network.
enum EnsoLegal {
    static var termsOfUse: String { "\(InternalURL.baseUrl)/\(TermsHandler.path)" }
    static var privacyNotice: String { "\(InternalURL.baseUrl)/\(PrivacyHandler.path)" }
}

private func page(_ resource: String, for request: URLRequest) -> (URLResponse, Data)? {
    guard let url = request.url,
          let path = Bundle.main.path(forResource: resource, ofType: "html"),
          let html = try? String(contentsOfFile: path, encoding: .utf8),
          let data = html.data(using: .utf8)
    else { return nil }
    return (InternalSchemeHandler.response(forUrl: url), data)
}

final class TermsHandler: InternalSchemeResponse {
    static let path = "about/terms"

    func response(forRequest request: URLRequest, useOldErrorPage: Bool = false) -> (URLResponse, Data)? {
        return page("Terms", for: request)
    }
}

final class PrivacyHandler: InternalSchemeResponse {
    static let path = "about/privacy"

    func response(forRequest request: URLRequest, useOldErrorPage: Bool = false) -> (URLResponse, Data)? {
        return page("Privacy", for: request)
    }
}

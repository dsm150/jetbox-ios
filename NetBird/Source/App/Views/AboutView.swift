//
//  AboutView.swift
//  NetBirdiOS
//
//  Created by Pascal Fischer on 01.08.23.
//

import SwiftUI
import NetBirdSDK

struct AboutView: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image("netbird-logo-menu")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120)
                        VStack(spacing: 4) {
                            Text("Version \(appVersion)")
                                .font(.subheadline)
                                .foregroundColor(Color("TextSecondary"))
                            Text("Core \(goVersion)")
                                .font(.caption)
                                .foregroundColor(Color("TextSecondary"))
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                // JetBox: лицензия форка и наша политика вместо страниц NetBird.
                if let termsURL = Optional(JetBoxConfig.licenseURL) {
                    Link(destination: termsURL) {
                        HStack {
                            Text("License agreement")
                                .foregroundColor(Color("TextPrimary"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(Color("TextSecondary"))
                                .font(.system(size: 14))
                        }
                    }
                }

                if let privacyURL = Optional(JetBoxConfig.privacyPolicyURL) {
                    Link(destination: privacyURL) {
                        HStack {
                            Text("Privacy policy")
                                .foregroundColor(Color("TextPrimary"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(Color("TextSecondary"))
                                .font(.system(size: 14))
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("\u{00A9} \(String(Calendar.current.component(.year, from: Date()))) JetNet")
                        .font(.footnote)
                        .foregroundColor(Color("TextSecondary"))
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Version of the Go client baked into NetBirdSDK.xcframework at compile time.
    private var goVersion: String {
        let version = NetBirdSDKGoClientVersion()
        return version.isEmpty ? "unknown" : version
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}

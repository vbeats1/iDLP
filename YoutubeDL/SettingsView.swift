//
//  SettingsView.swift
//  iDLP
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var soundcloudToken: String = ""
    @State private var showTokenAlert = false
    
    private var isTokenSaved: Bool {
        !soundcloudToken.isEmpty && soundcloudToken == app.soundcloudOAuthToken
    }
    
    private var buttonIcon: String {
        isTokenSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
    }
    
    private var buttonText: String {
        isTokenSaved ? "Token Saved" : "save token"
    }
    
    private var buttonColor: Color {
        isTokenSaved ? .green : .blue
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with blur effect
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // SoundCloud OAuth Token Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundStyle(.blue.gradient)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SoundCloud OAuth Token")
                                        .font(.headline)
                                    
                                    Text("Enable higher quality downloads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            // Glass morphism card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OAuth Token")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                SecureField("Enter SoundCloud OAuth token", text: $soundcloudToken)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial)
                                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                                    }
                                
                                if isTokenSaved {
                                    HStack {
                                        Text("Token saved")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        
                                        Spacer()
                                        
                                        Button("Clear") {
                                            soundcloudToken = ""
                                            app.soundcloudOAuthToken = nil
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                            }
                            
                            Button {
                                if soundcloudToken.isEmpty {
                                    showTokenAlert = true
                                } else {
                                    app.soundcloudOAuthToken = soundcloudToken
                                }
                            } label: {
                                HStack {
                                    Image(systemName: buttonIcon)
                                    Text(buttonText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(buttonColor.gradient)
                                        .shadow(color: buttonColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            }
                            .disabled(soundcloudToken.isEmpty)
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 5)
                        }
                        
                        // Info section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to get a SoundCloud OAuth Token")
                                .font(.headline)
                            
                            Text("1. Visit soundcloud.com and log in\n2. Open your browser's Developer Tools (F12 or right-click → Inspect)\n3. Go to Application/Storage → Cookies → soundcloud.com\n4. Find the 'oauth_token' cookie and copy its value")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        }
                    }
                    .padding()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
            .onAppear {
                soundcloudToken = app.soundcloudOAuthToken ?? ""
            }
            .onChange(of: app.soundcloudOAuthToken) { oldValue, newValue in
                if let token = newValue {
                    soundcloudToken = token
                } else {
                    soundcloudToken = ""
                }
            }
            .alert("Token Required", isPresented: $showTokenAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a SoundCloud OAuth token to enable higher quality downloads.")
            }
        }
    }
}

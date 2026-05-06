// SupabaseConfig.swift
// Replace the placeholder strings with your real Supabase credentials.
// The anon key is safe to embed — RLS restricts writes to INSERT only.

import Foundation

enum SupabaseConfig {
    static let url     = "https://nvmphccjysdhacqzbudj.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52bXBoY2NqeXNkaGFjcXpidWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMzUyNjIsImV4cCI6MjA5MzYxMTI2Mn0.Kc99xFs6tiwcTTnmAfsyxrYS4WSHEOb_yHVfrWKnj_Y"

    static let scoresURL: URL = {
        guard let url = URL(string: "\(url)/rest/v1/scores") else {
            fatalError("SupabaseConfig: invalid URL — check your url constant: \(url)")
        }
        return url
    }()
}

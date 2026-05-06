// SupabaseConfig.swift
// Replace the placeholder strings with your real Supabase credentials.
// The anon key is safe to embed — RLS restricts writes to INSERT only.

import Foundation

enum SupabaseConfig {
#if DEBUG
    static let url     = "https://YOUR_DEV_PROJECT.supabase.co"
    static let anonKey = "YOUR_DEV_ANON_KEY"
#else
    static let url     = "https://YOUR_PROD_PROJECT.supabase.co"
    static let anonKey = "YOUR_PROD_ANON_KEY"
#endif

    static var scoresURL: URL {
        URL(string: "\(url)/rest/v1/scores")!
    }
}

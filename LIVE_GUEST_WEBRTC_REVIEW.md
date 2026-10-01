# Bingo Live Guest WebRTC — review package

Branch: bingo-live-guest-webrtc-review-2026-10-01

This package does not alter production or execute SQL.

Files:
- supabase/bingo_change_live_guest_webrtc.sql — RLS-protected host/guest request + WebRTC signaling tables.
- assets/bingo-live-guest-webrtc.js — browser WebRTC signaling client.

Integration target: existing Live Studio UI. Preserve Flip, Dual Cam, Mic, Close and comments. Replace the dependency-warning state with Request to Join / pending requests / Accept / Decline / Remove.

Production dependency: configure authenticated TURN credentials in window.BINGO_LIVE_ICE_SERVERS. STUN-only is intentionally not considered production-ready on mobile networks.

Security note: SQL is review-only. Validate policies before execution.
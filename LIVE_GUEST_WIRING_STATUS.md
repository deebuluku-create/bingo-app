# Live Studio wiring status

Review branch only; production unchanged.

The Live Guest module and UI bridge are now staged. The bridge preserves the current studio controls and adds the remote guest video as an overlay when WebRTC emits a remote stream.

Important: the 4.1 MB monolithic BINGO_MASTER_CURRENT_VERIFIED.html cannot be safely retrieved through the GitHub connector in this environment, so it has NOT been blindly rewritten. The bridge is staged as a separate asset for controlled inclusion/deployment.

Before production:
1. review/execute supabase/bingo_change_live_guest_webrtc.sql;
2. enable Realtime for both new tables;
3. configure authenticated TURN credentials;
4. include assets/bingo-live-guest-webrtc.js and assets/bingo-live-guest-ui.js in the master HTML;
5. bind existing Guests controls to BingoLiveGuestUI;
6. test host + guest on two authenticated Android devices and on separate networks.

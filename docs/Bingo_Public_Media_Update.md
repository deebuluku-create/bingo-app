# Public media update — 1 October 2026

The current mother HTML preserves the original logo, typography, Cockpit and Messenger.

- Removes seeded vehicle and catalogue listings, including fabricated view totals.
- Published Bingo posts remain readable anonymously under existing moderated storage policies. Media links expire safely, clear failed requests and retry. Only the visible Home video plays; it starts muted, with a visible sound control and accurate playback errors.
- Home, Wall, detail and profile use the same original record identifiers. Existing vehicle, property/stay, food and Bingo post layouts are preserved. Real spare/household listings and vacancies now use shared Supabase records rather than device-only publication.
- Profile previews show four mixed media tiles across, or two on narrow phones. Guests can view public post previews while existing member-only contact controls remain gated.
- Shared counts start from zero when this update is installed: views qualify after 2 seconds visible; photo views require a loaded image; video watches require 3 seconds of actual visible playback. Counts deduplicate signed-in accounts or anonymous browser identifiers. They are not verified unique people or fraud-resistant prize rankings. No historical counts are fabricated.
- Existing identifiable device-only jobs/items are retained as owner drafts. They are not silently published. Owners can edit and publish their old vacancy drafts through the cloud-backed form.

## Backend changes

Applied `bingo_change_public_media.sql`: category listings with owner-only writes, private category photo storage, private event records and narrowly granted aggregate/record RPCs. Published public visibility does not expose hidden Bingo posts, paused jobs or viewer identities.

The reusable-sound FFmpeg worker from the previous change still needs a running server. This update does not claim sound extraction or reusable attribution is active.

Catalogue categories without an implemented publisher remain empty; removing demonstration records does not create a new publisher for those categories.

## Validation

All inline scripts and the extracted module pass Node syntax checks. `node tests/public-media.test.cjs` covers source filtering, category distribution, media filters, frontend deduplication, authenticated persistence requests and actual save error messages.

Supabase transactions (rolled back) verify authenticated listing insert, anonymous public read, deduplicated counters, rejection of nonexistent/hidden posts and private viewer-event permissions. Live anonymous preview checks confirm real published videos load, the active Home video plays muted automatically, sound plays after clicking the sound control, public profile previews use four columns, and offscreen videos pause. Guest preview clicks close the popup before opening the original post. Complete uploads through a new member account and cross-browser playback require live account testing; these are not inferred from syntax or mocked frontend tests.

# Integrated Bingo sounds

Implemented in BINGO_MASTER_CURRENT_VERIFIED.html: sound controls in Home topic cards, Wall/profile topic cards, video viewer and existing composer; upload/video/photo/camera selection; synchronized preview; real Supabase sound/job loading, private upload progress and a ready-job resume flow.

Supabase migration bingo_reusable_sounds_integration was applied on 2026-10-01. RLS protects original credit and member jobs. Authenticated members cannot insert sound attribution, modify jobs or claim processing jobs. Existing four video posts were queued in original publication order. New ordinary video posts are queued by a database trigger; ordinary posting is preserved. Recognition assigns no public credit before it completes.

## Remaining deployment requirement
The trusted worker is NOT running. An always-on server/container with Python 3.11+, FFmpeg/FFprobe (Chromaprint, H264 and AAC) must run worker.py with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY supplied privately by that host. No secret is stored here. Do not run this in the public webroot. The .htaccess denies web access to this directory.

Without this worker the website explicitly reports processing unavailable. No sound-with-media post is announced as published. Browser preview test fixtures do not change that fact.

## Worker behaviour
Serialized claims process original uploads by publication order. Audio is decoded/normalised, PCM-hashed and compared to saved acoustic fingerprints before new credit is accepted. The original profile comes from the source post, never from a requesting member. Very short or uncertain near matches go to review. Matched copies retain saved credit. Selected audio replaces media audio; a photo becomes an eight-second MP4. Finished files stay private to the member until they resume, preview and publish through the normal composer.

A worker crash leaves a processing job held, rather than allowing a second worker to assign concurrent credit. After confirming the old worker is stopped, an operator must inspect/retry that job. No automatic destructive cleanup or reassignment is included. Moderation of recognition review jobs, media retention cleanup and representative altered/trimmed audio testing remain operational requirements. Photo duration is eight seconds in this integration. Existing post editing does not recompose a replacement soundtrack. Other marketplace listing types have not received sound registration in this change.

## Verification
- SQL checks on live database: RLS on all three new tables; member credit/job writes denied; member worker claim and anonymous queue denied; a session without an identity sees zero jobs. Processor status is offline.
- Integrated UI fixtures: topic sound_id mapping, credited profile ID, Home/Wall/composer controls, sound library and offline rejection; no page JavaScript errors. External APIs/render side effects were stubbed in this fixture test.
- Worker with mocked transport and actual FFmpeg: source owner credit (not requester), duplicate reuse, photo+sound MP4 with video/audio streams, ready job states. This is not a live production media-flow test.
- Real account/camera/mobile upload/recognition-to-publication has NOT been fully tested. Do not call the complete feature operational until worker deployment and those checks pass.

Intentional advisor notices: the heartbeat table is service-role only with no client RLS policies; the public online-status function exposes only a boolean; authenticated queue RPC validates auth.uid(), source visibility, sound visibility, own uploaded storage path and rate limit. Existing unrelated advisories were not changed.

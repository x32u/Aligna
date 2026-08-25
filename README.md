# Aligna

Aligna is a native iOS meeting intelligence and project-management application.
It records meetings locally, creates multilingual transcripts, generates
structured meeting notes, and keeps AI-suggested outcomes grounded in transcript
evidence.

## Technology

- Swift and SwiftUI
- Supabase Auth, PostgreSQL, Realtime, private Storage, and Edge Functions
- Groq Whisper Large V3 for multilingual transcription
- Groq GPT-OSS 120B for structured meeting analysis
- FluidAudio for optional on-device speaker diarization and voice matching
- Swift Testing and XCUITest

## Project structure

- `Aligna/App` - application navigation
- `Aligna/Core` - design system, configuration, session, and validation
- `Aligna/Data` - repositories, DTOs, and Supabase implementations
- `Aligna/Features` - authentication, dashboard, meetings, settings, and workspaces
- `Aligna/Services` - audio, processing, Live Activity, and voice services
- `Aligna/Shared` - reusable views and domain models
- `supabase` - database migrations, Edge Functions, and SQL tests

## Local setup

1. Open `Aligna.xcodeproj` in Xcode.
2. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`.
3. Add the Supabase project URL and publishable key to the local secrets file.
4. Select the main Aligna scheme and run it on an iOS simulator or physical
   iPhone.

`Config/Secrets.xcconfig` is intentionally excluded from Git. Groq and service
role credentials belong only in Supabase Edge Function secrets and must never be
placed in the iOS application or repository. See `SUPABASE_SETUP.md` for backend
deployment details.

## Current capabilities

- Email/password authentication, verification, recovery, and session restoration
- Workspace and member collaboration
- Local M4A meeting recording and playback
- Private, authenticated audio-processing workflow
- Multilingual transcript and AI-generated meeting outcomes
- Optional on-device voice enrollment and speaker attribution
- Meeting create, read, update, and delete operations
- Light, dark, and system appearance modes

## Verification

The project includes Swift unit tests, UI tests, Supabase SQL tests, and a
physical-device transcription test plan in `TRANSCRIPTION_TEST_PLAN.md`.

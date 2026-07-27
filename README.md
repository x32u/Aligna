# Aligna

Aligna is an AI-powered mobile meeting intelligence and project management
application. This initial milestone contains a fully navigable mock experience;
backend authentication, audio processing, AI extraction, and persistence are
intentionally represented by typed service interfaces only.

## Stack

- Expo SDK 57
- React Native 0.86
- TypeScript in strict mode
- Expo Router
- Automatic light and dark themes

## Run locally

```bash
npm install
npm run ios
```

The first iOS launch requires an installed Xcode simulator runtime. You can also
start Metro without opening a simulator:

```bash
npm start
```

## Quality checks

```bash
npm run typecheck
npm run lint
npx expo-doctor
```

## Routes

- `/login` — mock sign-in
- `/create-account` — mock workspace creation
- `/dashboard` — project overview and recent meeting review
- `/meeting` — recording/upload placeholder
- `/results` — summary, transcript preview, and human AI-task review
- `/timeline` — Gantt-style project schedule and dependencies

Route files remain intentionally thin. Screen implementations live under
`src/features`, reusable primitives under `src/components`, and future backend
contracts under `src/services`.

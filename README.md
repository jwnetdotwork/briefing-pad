# BriefingPad

BriefingPad is a Mac app that helps with giving advice on the demonstration portions of the *Christian Life and Ministry* meeting.
Based on recording transcriptions, it can analyze observation notes and generate comment suggestions for short reviews.

Part information can be imported from Notion or created manually within the app. For Notion-imported sessions, AI memo generated at the end of a part can be written back to Notion. For manually created sessions, AI memo stays within the app and does not sync to Notion.

## Main Uses

- Import meeting scripts placed in Notion into the app
- Manually create new sessions and parts within the app
- Record per part and accumulate transcriptions
- Automatically pick up observation notes and positive item candidates from transcriptions
- Generate AI memo for short reviews after a part ends
- For Notion-imported sessions, sync generated AI memo back to Notion

## How to Create Part Information

| Route | Method | AI Memo handling |
| --- | --- | --- |
| Notion import | Import a Notion page and turn existing part info into a session | Can write back to the corresponding `🤖 AI memo` block |
| Manual creation | Create a new session in the app and enter part info via `Add Part` | Retained only within the app; cannot be written back to Notion |

AI memo generation itself is available for both routes, but Notion sync is possible only for Notion-imported sessions.

## System Requirements

- macOS 26 Tahoe or later
- OpenAI API Key
- Notion integration token (only when using Notion import)

## Quick Start

You can use BriefingPad without Notion.

1. Install the app
2. Allow the warning on first launch
3. Enter your OpenAI API Key in Settings
4. Create a new session
5. Add a part
6. Start recording
7. Press "Finish Part"
8. Review the AI memo

## Preparation

### 1. Prepare an OpenAI API Key

An OpenAI API key is required for evaluating observation notes and generating AI memo.
Create an API key on OpenAI's developer page. Even if you subscribe to ChatGPT Plus, separate API usage setup is required.
OpenAI API usage incurs pay-as-you-go charges. Check OpenAI's pricing page before use.
Do not share your API key with others.

### 2. Create a Notion Integration (only when using Notion import)

This setup is only needed if you import part information from Notion.
If you create sessions manually, no Notion configuration is required.
Create a new connection from the Notion [Developer Portal](https://app.notion.com/developers/connections) and obtain an integration token (access token).

### 3. Share the Target Page in Notion (only when using Notion import)

Settings → Connections → Manage → Manage connections and tokens → All connections → "..." on the target connection → Manage connection.
Under Page Access Management, check the target Notion page or parent page to allow the connection to access it.

Insufficient sharing will result in a permission error during import.

## Download and Install

- Download a .dmg or .zip file from the [Releases page](https://github.com/jwnetdotwork/briefing-pad/releases).

### For DMG

1. Double-click the downloaded .dmg and drag "BriefingPad.app" into the "Applications" folder.

### For ZIP

1. Double-click the downloaded .zip to extract it, then drag "BriefingPad.app" into the "Applications" folder.

## How to Launch

This app is currently not notarized by Apple, so a warning will appear on first launch. After verifying the source of the app, follow the steps below to launch it.

1. Double-click "BriefingPad.app" in the "Applications" folder.
2. A message will appear: "BriefingPad.app is not open. Apple could not verify that BriefingPad.app is free of malware that may harm your Mac or compromise your privacy." This is because the app does not use an Apple-issued certificate for signing.
3. Click "Done" to close the message.
4. Open macOS "System Settings" → "Privacy & Security" and scroll down to "Security".
5. You will see "BriefingPad.app was blocked to protect your Mac." Click "Open Anyway".
6. A dialog will appear — click "Open Anyway".
7. Enter your Mac login password or use Touch ID to authorize the launch.
8. When a dialog appears about using information in your keychain, enter your login password and click "Allow" or "Always Allow".

## First Recording

On the first recording, macOS will ask for microphone permission.
Select "Allow".
If you accidentally denied it, go to System Settings → Privacy & Security → Microphone and enable BriefingPad.

## Initial Settings

1. Open `Settings` from the top-right of the app
2. Save your `OpenAI API Key`
3. Save your `Notion Integration Token` (optional)
4. Adjust `API Endpoint (optional)`, `Model Name (optional)`, `Session sort order`, and `Transcription Language` as needed
5. Press `Save`

Saved information: `OpenAI API Key` and `Notion Integration Token` are stored in the keychain; other settings are stored in app preferences.

### Settings Items

| Item | Description | Storage | Notes |
| --- | --- | --- | --- |
| `OpenAI API Key` | API key used for transcription analysis and AI memo generation | Keychain | If left blank, OpenAI API is unavailable |
| `Notion Integration Token` | Token used for Notion import and writing back to Notion | Keychain | Can be left unset if not using Notion |
| `API Endpoint (optional)` | Base URL for sending to OpenAI-compatible APIs | App preferences | For using providers other than OpenAI. `/chat/completions` is appended automatically, so do not include it |
| `Model Name (optional)` | Model name used for AI memo generation and analysis | App preferences | If blank, defaults to `gpt-5.4-mini-2026-03-17` |
| `Session sort order` | Sort order for the session list | App preferences | Choose from: `Name (Ascending)`, `Name (Descending)`, `Updated (Oldest)`, `Updated (Newest)`, `Created (Oldest)`, `Created (Newest)`. Default is `Created (Newest)` |
| `Transcription Language` | Language setting used for transcription | App preferences | Choose from `SpeechTranscriber` supported locales. When not set, automatically determined based on system language. Falls back to `ja-JP` or an available locale if no match is found |

## Notion Import Procedure

1. Open `Import from Notion` from the top-right of the app
2. Paste a Notion page URL or page ID
3. Press `Preview`
4. Check the session name, part list, and number of unparsed blocks
5. If everything looks good, press `Import`

URLs in `https://app.notion.com/...` format or direct page IDs can both be used.

## Manual Creation Flow

1. Create a new session from the session selector
2. Register parts using `Add Part`
3. Select a part to record, transcribe, and generate AI memo

Manually created sessions are self-contained within the app. Nothing is written back to Notion.

## Screen Overview

### Top Bar

- Select Session
- New Session
- Add Part
- Delete menu
- Import from Notion
- Settings

### Part List

Displays the parts contained in the current session in a horizontal layout.

Use the left and right arrows to move between parts.

### Recording and Playback

- `Start` — begin recording
- `Pause` — pause recording
- `Play` — play saved audio
- `Stop Playback` — stop playback
- `Finish Part` — finalize the current part

### Transcription

Speech captured during recording is displayed here.

### Observation Notes / Positive Candidates

Candidates are automatically displayed based on the transcription content.

### 🤖 AI Memo

Comment material for short reviews is displayed here.

- Automatically generated when a part ends
- Can be manually `Regenerate`d
- For Notion-imported parts, reflected in the corresponding `🤖 AI memo` block
- For manually created parts, display is limited to within the app

## Delete Menu

From `Delete` in the top bar, you can delete sessions and parts. Deletion is not possible while recording, during playback, or during final processing.

### Delete Session

- Deletes the currently selected session entirely
- Removes all local storage under the session
- Targets include parts, audio, transcriptions, AI analysis results, AI memo, and sync state
- Does not delete the original Notion page

### Delete Part

- Deletes the currently selected part entirely
- Removes local storage for the part and removes it from the session
- Targets include audio, transcription, AI analysis results, AI memo, and analysis state
- Does not delete the original Notion block

### Delete Part Data

- Deletes only data while keeping the part definition
- Options: `All`, `Audio only`, `Transcription only`, `AI analysis results`
- Use when you want to keep the part but redo recording or analysis

## Notion Page Structure

This section is for template guidance when importing from Notion. It is not required for manual creation.

Import relies heavily on the block structure of the Notion page.

In particular, chapter headings and part headings should follow this format:

```md
Treasures from God's Word   <- Heading 2
  3. Part name               <- Heading 3
    (4 min.) Scene or material
    📓 Learning points
     • ...
    👀 Observation notes
     • ...
    👍 Where and how it was good
     • ...
    🤖 AI memo
```

### Recognized Headings

In Notion, use "Heading 2" for section titles and "Heading 3" for each part title.

Example:

- Heading 2: Treasures from God's Word
- Heading 3: 3. Bible Reading — John Smith

### Section Headings

Use the following two chapter names as-is:

- `Treasures from God's Word`
- `Apply Yourself to the Field Ministry`

Blocks outside these two sections are generally excluded from import.

### Part Headings

Part headings must start with a number followed by a period, e.g. `1.` `2.` `3.`.

Examples:

- `3. Bible Reading — John Smith`
- `4. Starting a Conversation — Jane Doe/John Doe`

### Layout Tips for Smooth Import

- Place time, setting, and scene immediately after the part heading
- Keep each chapter heading to a single block, single line
- Keep each item to one block
- Use the same chapter heading text every time

## Emoji Labels to Use

The following labels work reliably with current import:

- `📓 Learning points`
- `👀 Observation notes`
- `👍 Where and how it was good`
- `🤖 AI memo`

### Label Usage Tips

- Keep the emoji and wording identical each time
- Place labels in standalone blocks
- Put bullet points or short paragraphs below each label
- Do not mix multiple labels in one block
- Do not paraphrase label names
- `🤖 AI memo` is how it appears on the app screen

### Labels Best Avoided

The following labels are reserved in code but are not primary targets for automatic import at this time:

- `☔ Next step`
- `👪 Summary`
- `Prior information`

Placing `Prior information` as a supplemental field is fine, but it is not treated as a structured item.

## AI Memo Write Destination

`🤖 AI memo` is the display name used in the app.

The app generates AI memo when a part ends or on manual regeneration.

For Notion-imported sessions, it syncs to the corresponding `🤖 AI memo` block. Manually created sessions have no Notion write destination, so AI memo is kept only within the app.

When writing back to Notion, the output is labeled `🤖 AI memo`, so the template can use either `🤖 AI memo` or the equivalent. For consistency, matching the app's `🤖 AI memo` label is clearest.

## When Import Doesn't Work Well

- If the preview shows many unparsed blocks, review the heading hierarchy
- Check that chapter names match exactly
- Check that part headings start with a number and period, e.g. `3.`
- Check that the Notion page is shared with the integration
- Check that the OpenAI API Key and Notion token are saved in Settings

## Speech Recognition Usage

Requires an internet connection, or may function with on-device macOS speech recognition. See Apple's documentation for supported languages.

## Privacy Notice

When generating AI memo, transcription content and related notes are sent to the OpenAI API.
Exercise caution if they contain personal information or content you do not wish to disclose.

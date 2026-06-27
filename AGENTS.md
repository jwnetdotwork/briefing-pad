## 対象OS　
- macOS 26.5
- MACOSX_DEPLOYMENT_TARGET = 26.5;

## 使用API
- macOS 26から使えるようになった SpeechTranscriber を使用します。
- 旧API SFSpeechTranscriber は使用しません。


個人用プロジェクトなので、以下は避けてください｡
- 過剰なエラーハンドリングや
- LLMの出力に依存したテストコード

通常のビルドは署名まわりで止まるため、次でビルド確認します。
`xcodebuild build-for-testing -project BriefingPad.xcodeproj -scheme BriefingPad -destination 'platform=macOS' -derivedDataPath /private/tmp/DerivedDataBriefingPad CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

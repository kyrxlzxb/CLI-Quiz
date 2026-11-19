# CLI Quiz

Windows PowerShell terminal quiz. The original `quiz.cmd` and `questions.json`
remain the default bank. `CLI-Quiz-CN.zip` is the existing Chinese package and
has not been changed.

## DVA-C02

Run `quiz-dva.cmd`, or from PowerShell:

```powershell
.\quiz.ps1 -Bank dva
```

Choose `all`, a single question number such as `403`, or an inclusive range such
as `403-551`. Enter one answer letter, or comma-separated letters for a multiple
choice question (`B,C`). Enter `q` at a prompt to quit.

- 551 records from the reviewed DVA PWA bank; existing stable question numbers
  and corrected answers are preserved. The first 402 records retain their earlier
  review; records 403–551 are the reviewed supplement.
- English question stems and choices; existing Chinese explanations and audit
  notes are retained. No new translations were added.
- Audit labels appear before answering. Explanations are shown after both correct
  and incorrect DVA answers, including conditional or outdated-answer notes.
- Ten incomplete/ambiguous supplement records use self-review: press Enter to
  see the explanation, then `y` for understood or `n` for needs review. They are
  excluded from the automatic score and logged separately.
- 22 local images include question diagrams and image-only answer choices. Their
  paths are printed next to the question/choice. Enter `i` at the answer prompt
  to open the current question's images in your default viewer; then return to
  the terminal. No online image download is needed. In a headless terminal,
  transfer/open the printed local files on a device with an image viewer.
- Wrong answers go to `mistakes-dva.jsonl`; self-reviews go to
  `reviews-dva.jsonl`. The original bank continues to use `mistakes.jsonl`.
- The source has a duplicate pair (source questions 446 and 483); these are
  preserved with their source metadata. 551 is a record count, not a guarantee
  of semantic uniqueness.

The reviewed source is the PWA working branch commit `0955345`. Import metadata
and the exact source JSON checksum are in `data/dva-import.json`. Each question
retains its review status, explanation and available official evidence links.

## Rebuild and test

Node.js is only needed for importing and running development tests, not for
playing the quiz.

```powershell
node scripts/import-dva.cjs ..\aws-quiz-pwa-offline
node --test tests/dva-cli.test.cjs
```

Use the reviewed PWA checkout at commit `0955345` as the import source. The
importer preserves its JSON and copies only the referenced DVA image assets;
it does not replace the existing default bank or Chinese ZIP package.

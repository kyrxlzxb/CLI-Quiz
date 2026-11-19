// node scripts/import-dva.cjs <path-to-reviewed-pwa-repository>
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
assert(process.argv[2], 'Pass the reviewed PWA repository directory.');
const source = path.resolve(process.argv[2]);
const root = path.resolve(__dirname, '..');
const bytes = fs.readFileSync(path.join(source, 'data/questions-dva.json'));
const questions = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
assert.equal(questions.length, 551);
assert.equal(new Set(questions.map(q => q.qid)).size, 551);
const images = new Set();
questions.forEach((q, i) => {
  assert.equal(q.qnum, i + 1);
  assert(q.question_text && q.options.length);
  const review = q.special_data?.kind === 'review';
  assert(review ? q.options.every(o => !o.is_correct) : q.options.some(o => o.is_correct));
  for (const media of [...(q.media || []), ...q.options.map(o => o.media).filter(Boolean)]) {
    assert(/^assets\/dva(?:-supplement)?\/[\w.-]+\.(png|jpg|jpeg)$/.test(media.src));
    assert(fs.existsSync(path.join(source, media.src)));
    images.add(media.src);
  }
});
fs.mkdirSync(path.join(root, 'data'), {recursive: true});
for (const file of images) {
  fs.mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
  fs.copyFileSync(path.join(source, file), path.join(root, file));
}
// Keep all corrected answers, audit notes, stable IDs and original source metadata.
fs.writeFileSync(path.join(root, 'data/questions-dva.json'), bytes);
fs.writeFileSync(path.join(root, 'data/dva-import.json'), JSON.stringify({
  exam: 'DVA-C02', records: questions.length, self_review_records: questions.filter(q => q.special_data?.kind === 'review').length,
  source: 'kyrxlzxb/aws-quiz-pwa-offline', source_commit: '0955345',
  sha256: crypto.createHash('sha256').update(bytes).digest('hex'), images: [...images].sort(),
}, null, 2) + '\n');
console.log(`Imported ${questions.length} DVA records and ${images.size} offline images.`);

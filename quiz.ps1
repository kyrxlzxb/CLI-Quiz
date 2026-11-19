param([ValidateSet('default', 'dva')][string]$Bank = 'default')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-QuizInput($prompt) {
    [Console]::Write($prompt)
    $line = [Console]::ReadLine()
    if ($null -eq $line) { return 'q' }
    return $line.Trim().ToLowerInvariant()
}

function Get-QuestionRange($inputText, $first, $last) {
    if ($inputText -eq 'all') { return $first, $last }
    if ($inputText -notmatch '^([0-9]+)(?:\s*-\s*([0-9]+))?$') { return }

    $start = 0
    if (-not [int]::TryParse($Matches[1], [ref]$start)) { return }
    $end = $start
    if ($Matches.ContainsKey(2) -and -not [int]::TryParse($Matches[2], [ref]$end)) { return }
    if ($start -ge $first -and $end -le $last -and $start -le $end) {
        return $start, $end
    }
}

function Get-SelectedAnswer($inputText, $keys, $count) {
    $choices = @($inputText.ToUpperInvariant() -split '\s*[,\uFF0C]\s*')
    $distinct = @($choices | Sort-Object -Unique)
    if ($choices.Count -ne $count -or $distinct.Count -ne $count) { return }
    foreach ($choice in $distinct) {
        if ($choice -notin $keys) { return }
    }
    return $distinct
}

function Get-QuizMedia($question, $root) {
    $items = @($question.media)
    foreach ($option in $question.options) { if ($option.media) { $items += $option.media } }
    foreach ($item in $items) {
        if (-not $item.src) { continue }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $root $item.src))
        $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetExtension($fullPath) -notin @('.png', '.jpg', '.jpeg', '.gif', '.webp')) {
            throw "Unsupported image path: $($item.src)"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing image: $fullPath" }
        $fullPath
    }
}

function Write-QuizRecord($path, $record) {
    $line = ConvertTo-Json -InputObject $record -Compress -Depth 8
    [IO.File]::AppendAllText($path, "$line`n", [System.Text.UTF8Encoding]::new($false))
}

try {
    $root = $PSScriptRoot
    $bankPath = Join-Path $root 'questions.json'
    $logPath = Join-Path $root 'mistakes.jsonl'
    if ($Bank -eq 'dva') {
        $bankPath = Join-Path $root 'data/questions-dva.json'
        $logPath = Join-Path $root 'mistakes-dva.jsonl'
    }
    $reviewLogPath = Join-Path $root 'reviews-dva.jsonl'
    $bankRecords = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($bankPath))
    $questions = @($bankRecords | Sort-Object qnum)
    if (-not $questions.Count) { throw 'The question bank is empty.' }
    $first = $questions[0].qnum
    $last = $questions[-1].qnum

    [Console]::WriteLine('CLI Quiz')
    if ($Bank -eq 'dva') { [Console]::WriteLine("AWS DVA-C02 - $($questions.Count) records. English questions; reviewed explanations retained.") }
    [Console]::WriteLine('Enter q at any prompt to quit.')
    do {
        $inputText = Read-QuizInput "Question range ($first-$last, e.g. 20-40, or all): "
        if ($inputText -eq 'q') { exit 0 }
        $range = @(Get-QuestionRange $inputText $first $last)
        if ($range.Count -ne 2) {
            [Console]::WriteLine('Enter a valid question number or an inclusive range.')
            continue
        }

        $selected = @($questions | Where-Object { $_.qnum -ge $range[0] -and $_.qnum -le $range[1] })
        if (-not $selected.Count) { [Console]::WriteLine('No questions in that range.') }
    } until ($selected.Count)
    [Console]::WriteLine("`n$($selected.Count) question(s) selected.")

    $answered = 0
    $correct = 0
    $visited = 0
    $selfReviewed = 0
    $needsReview = 0
    foreach ($question in $selected) {
        $visited++
        $options = @($question.options | Sort-Object sort_order)
        $keys = @($options.key)
        $expected = @($options | Where-Object is_correct | ForEach-Object { $_.key } | Sort-Object)
        $expectedText = $expected -join ', '
        [Console]::WriteLine("`nQuestion $($question.qnum) ($visited/$($selected.Count))")
        if ($question.audit_label) { [Console]::WriteLine("Review status: $($question.audit_label)") }
        [Console]::WriteLine($question.question_text)
        foreach ($option in $options) {
            if ($option.text -or $option.media) { [Console]::WriteLine("$($option.key). $($option.text)") }
            if ($option.media) { [Console]::WriteLine("   Image: $($option.media.src)") }
        }
        $mediaPaths = @(Get-QuizMedia $question $root)
        if ($mediaPaths.Count) {
            [Console]::WriteLine('Images (enter i at the answer prompt to open locally):')
            foreach ($imagePath in $mediaPaths) { [Console]::WriteLine("  $imagePath") }
        }

        if ($question.special_data.kind -eq 'review') {
            [Console]::WriteLine('Insufficient information: self-review only, excluded from automatic scoring.')
            $inputText = Read-QuizInput 'Press Enter to show the review, or q to quit: '
            if ($inputText -eq 'q') { break }
            [Console]::WriteLine("Explanation:`n$($question.explanation_en)")
            do {
                $inputText = Read-QuizInput 'Self-review: y = understood, n = needs review, q = quit: '
                if ($inputText -notin @('y', 'n', 'q')) { [Console]::WriteLine('Enter y, n, or q.') }
            } until ($inputText -in @('y', 'n', 'q'))
            if ($inputText -eq 'q') { break }
            $selfReviewed++
            if ($inputText -eq 'n') { $needsReview++ }
            Write-QuizRecord $reviewLogPath ([ordered]@{
                timestamp = [DateTime]::UtcNow.ToString('o'); bank = $Bank; qid = $question.qid
                questionNumber = $question.qnum; result = $(if ($inputText -eq 'y') { 'understood' } else { 'needs_review' })
                explanation = $question.explanation_en
            })
            continue
        }
        if (-not $expected.Count) { throw "Question $($question.qnum) has no verified answer and is not marked for self-review." }

        $prompt = 'Answer (one letter): '
        if ($expected.Count -gt 1) {
            $prompt = "Answer ($($expected.Count) letters, separated by commas): "
        }
        do {
            $inputText = Read-QuizInput $prompt
            if ($inputText -eq 'q') { break }
            if ($inputText -eq 'i' -and $mediaPaths.Count) {
                foreach ($imagePath in $mediaPaths) { Invoke-Item -LiteralPath $imagePath }
                $answer = @()
                continue
            }
            $answer = @(Get-SelectedAnswer $inputText $keys $expected.Count)
            if (-not $answer.Count) {
                [Console]::WriteLine("Enter $($expected.Count) distinct choice(s) from $($keys -join ', ').")
            }
        } until ($answer.Count)
        if ($inputText -eq 'q') { break }

        $answered++
        if (($answer -join ', ') -eq $expectedText) {
            $correct++
            [Console]::WriteLine("Correct. Correct answer: $expectedText")
            if ($Bank -eq 'dva' -and $question.explanation_en) { [Console]::WriteLine("Explanation:`n$($question.explanation_en)") }
            continue
        }

        [Console]::WriteLine("Incorrect. Correct answer: $expectedText")
        $explanation = $question.explanation_en
        if (-not $explanation) { $explanation = 'No explanation available.' }
        [Console]::WriteLine("Explanation:`n$explanation")
        $mistake = [ordered]@{
            timestamp = [DateTime]::UtcNow.ToString('o')
            qid = $question.qid
            questionNumber = $question.qnum
            answer = $answer
            correctAnswer = $expected
            explanation = $explanation
        }
        Write-QuizRecord $logPath $mistake
    }
    [Console]::WriteLine("`nSession complete. $correct/$answered correct.")
    if ($answered -gt $correct) { [Console]::WriteLine("Mistakes saved to $([IO.Path]::GetFileName($logPath)).") }
    if ($selfReviewed) { [Console]::WriteLine("Self-reviewed: $selfReviewed; needs review: $needsReview. Saved to reviews-dva.jsonl (not included in score).") }
} catch {
    [Console]::Error.WriteLine("Quiz error: $($_.Exception.Message)")
    exit 1
}

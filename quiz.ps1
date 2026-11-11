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

try {
    $root = $PSScriptRoot
    $bankPath = Join-Path $root 'questions.json'
    $logPath = Join-Path $root 'mistakes.jsonl'
    $bank = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($bankPath))
    $questions = @($bank | Sort-Object qnum)
    $first = $questions[0].qnum
    $last = $questions[-1].qnum

    [Console]::WriteLine('CLI Quiz')
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
    foreach ($question in $selected) {
        $options = @($question.options | Sort-Object sort_order)
        $keys = @($options.key)
        $expected = @($options | Where-Object is_correct | ForEach-Object { $_.key } | Sort-Object)
        $expectedText = $expected -join ', '
        [Console]::WriteLine("`nQuestion $($question.qnum) ($($answered + 1)/$($selected.Count))")
        [Console]::WriteLine($question.question_text)
        foreach ($option in $options) {
            [Console]::WriteLine("$($option.key). $($option.text)")
        }

        $prompt = 'Answer (one letter): '
        if ($expected.Count -gt 1) {
            $prompt = "Answer ($($expected.Count) letters, separated by commas): "
        }
        do {
            $inputText = Read-QuizInput $prompt
            if ($inputText -eq 'q') { break }
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
        $record = ConvertTo-Json -InputObject $mistake -Compress
        [IO.File]::AppendAllText($logPath, "$record`n", [System.Text.UTF8Encoding]::new($false))
    }
    [Console]::WriteLine("`nSession complete. $correct/$answered correct.")
    if ($answered -gt $correct) { [Console]::WriteLine('Mistakes saved to mistakes.jsonl.') }
} catch {
    [Console]::Error.WriteLine("Quiz error: $($_.Exception.Message)")
    exit 1
}

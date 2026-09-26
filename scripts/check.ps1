# Re-read the pins in pins.json from GitHub and from the local master file.
# Exit 1 on any mismatch. This checks commits and status words, not the propositions.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$pins = Get-Content -Raw (Join-Path $root "pins.json") | ConvertFrom-Json
$fail = @()

function Assert-True($name, $ok, $detail) {
    if ($ok) { Write-Output "PASS  $name" }
    else { Write-Output "FAIL  $name  $detail"; $script:fail += $name }
}

function Get-Text($url) {
    $b64 = gh api $url --jq .content
    if (-not $b64) { throw "empty content from $url" }
    $clean = ($b64 | Out-String) -replace "\s", ""
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
}

$main = gh api repos/kaspanet/kccs/commits/main --jq .sha
Assert-True "kccs main" ($main -eq $pins.kccs_main) "live $main"

$kcc0 = Get-Text "repos/kaspanet/kccs/contents/kcc-0000.md?ref=$($pins.kccs_main)"
Assert-True "kcc-0000 Final" ($kcc0 -match "(?m)^Status: $($pins.kcc0_status_in_file)\s*$") "header missing"
Assert-True "kcc-0 ground truth sentence" ($kcc0 -match "does not make the\s+convention protocol ground truth") "sentence missing"
Assert-True "kcc-0 categories" ($kcc0 -match "\*\*Covenant\*\*" -and $kcc0 -match "\*\*Application\*\*" -and $kcc0 -notmatch "\*\*Asset\*\*") "category list drifted"

$readme = Get-Text "repos/kaspanet/kccs/contents/README.md?ref=$($pins.kccs_main)"
Assert-True "readme index still Draft for KCC-0" ($readme -match "\|\s*\[0\]\(kcc-0000\.md\).*Draft\s*\|") "index row changed"

foreach ($pair in @(
    @{ f = "kcc-0001.md"; s = $pins.kcc1_status },
    @{ f = "kcc-0002.md"; s = $pins.kcc2_status },
    @{ f = "kcc-0020.md"; s = $pins.kcc20_status }
)) {
    $text = Get-Text "repos/kaspanet/kccs/contents/$($pair.f)?ref=$($pins.kccs_main)"
    Assert-True "$($pair.f) $($pair.s)" ($text -match "(?m)^Status: $($pair.s)\s*$") "header missing"
}

$blob2 = gh api "repos/kaspanet/kccs/contents/kcc-0002.md?ref=$($pins.kccs_main)" --jq .sha
Assert-True "kcc-0002 blob" ($blob2.StartsWith($pins.kcc2_blob)) "live $blob2"
$kcc2 = Get-Text "repos/kaspanet/kccs/contents/kcc-0002.md?ref=$($pins.kccs_main)"
Assert-True "kcc-2 keyed hash" ($kcc2 -match 'Hash\(pubkey, UTF8\("PublicKeyHash"\)\)') "keyed sentence missing"

$blob20 = gh api "repos/kaspanet/kccs/contents/kcc-0020.md?ref=$($pins.kccs_main)" --jq .sha
Assert-True "kcc-0020 blob" ($blob20.StartsWith($pins.kcc20_blob)) "live $blob20"
$kcc20 = Get-Text "repos/kaspanet/kccs/contents/kcc-0020.md?ref=$($pins.kccs_main)"
Assert-True "kcc-20 amount preservation" ($kcc20 -match "preserve the total token amount") "preservation sentence missing"

$prHeads = @{
    "31" = $pins.pr31_head
    "30" = $pins.pr30_head
    "27" = $pins.pr27_head
    "24" = $pins.pr24_head
    "23" = $pins.pr23_head
    "20" = $pins.pr20_head
    "6"  = $pins.pr6_head
}
foreach ($n in $prHeads.Keys) {
    $pr = gh api "repos/kaspanet/kccs/pulls/$n" --jq "{sha:.head.sha, state:.state, merged:.merged}"
    $sha = ($pr | ConvertFrom-Json).sha
    $state = ($pr | ConvertFrom-Json).state
    $merged = ($pr | ConvertFrom-Json).merged
    Assert-True "pr $n head" ($sha.StartsWith($prHeads[$n]) -and $state -eq "open" -and $merged -eq $false) "live $sha state $state merged $merged"
}

$kcc20pr = Get-Text "repos/kaspanet/kccs/contents/kcc-0020.md?ref=$($pins.pr31_head)"
$hasDeadline = $kcc20pr -match "(?m)^Last-Call-Deadline:"
Assert-True "pr 31 Last Call without deadline" (($kcc20pr -match "(?m)^Status: Last Call\s*$") -and ($hasDeadline -eq $pins.pr31_has_last_call_deadline)) "deadline flag drifted"

$kcc2pr = Get-Text "repos/kaspanet/kccs/contents/kcc-0002.md?ref=$($pins.pr30_head)"
Assert-True "pr 30 unkeyed and reserved" ($kcc2pr -match "unkeyed ``Hash\(x\)``" -and $kcc2pr -match "MUST reject") "range text drifted"

$ref = gh api repos/argent-lang/kcc20-reference/pulls/$($pins.reference_pr) --jq "{sha:.head.sha, state:.state, merged:.merged}"
$refj = $ref | ConvertFrom-Json
Assert-True "reference pull" ($refj.sha -eq $pins.reference_head -and $refj.merged -eq $pins.reference_merged -and $refj.state -eq "open") "live $($refj.sha)"

$live = gh api repos/Manyfestation/kcc20-live/commits/main --jq .sha
Assert-True "kcc20-live tip" ($live.StartsWith($pins.kcc20_live_tip)) "live $live"

$kip = Get-Text "repos/kaspanet/kips/contents/kip-0020.md?ref=$($pins.kips_master)"
Assert-True "kip-20 Active" ($kip -match "(?m)^Status: $($pins.kip20_status)\s*$") "header missing"
$kipsMain = gh api repos/kaspanet/kips/commits/master --jq .sha
Assert-True "kips master" ($kipsMain -eq $pins.kips_master) "live $kipsMain"

$masterDir = "$env:USERPROFILE\kaspa-master-file-git"
$masterHead = (git -C $masterDir rev-parse HEAD).Trim()
Assert-True "master file head" ($masterHead -eq $pins.master_file) "live $masterHead"
$masterReadme = Get-Content -Raw (Join-Path $masterDir "README.md")
Assert-True "master Now KCC-0 Final in the file" ($masterReadme -match "KCC-0 \| \*\*Final in the file") "Now row missing"
Assert-True "master Now index leftover" ($masterReadme -match "still says Draft") "leftover sentence missing"
Assert-True "master Now KCC-20 Draft" ($masterReadme -match "KCC-20 file remains \*\*Draft\*\*") "Draft sentence missing"
Assert-True "master Now no L1 stable" ($masterReadme -match "No spendable L1 stable") "stable sentence missing"
$origin = (git -C $masterDir rev-parse origin/main).Trim()
Assert-True "master file matches origin/main" ($origin -eq $masterHead) "origin $origin"

$note = Get-Content -Raw (Join-Path $root "README.md")
Assert-True "note names Draft KCC-20" ($note -match "KCC-20 \| Draft") "table row missing"
Assert-True "note does not call KCC-20 Final" ($note -notmatch "KCC-20 is Final" -and $note -notmatch "KCC-20 Final") "forbidden phrase"
Assert-True "note does not announce Tether" ($note -notmatch "Tether announced" -and $note -notmatch "USDT is live on Kaspa") "forbidden phrase"
Assert-True "note keeps the ground-truth quote" ($note -match "does not make the convention protocol ground truth") "quote missing"

if ($fail.Count -gt 0) {
    Write-Output ("FAILED " + ($fail -join ", "))
    exit 1
}
Write-Output "ALL PASS"
exit 0

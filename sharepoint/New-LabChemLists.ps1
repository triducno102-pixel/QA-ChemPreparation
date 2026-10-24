#Requires -Version 7.2
<#
.SYNOPSIS
    Tạo 10 SharePoint list của ứng dụng LabChem theo LabChem.Schema.ps1.

.DESCRIPTION
    - Idempotent: chạy lại sẽ bỏ qua list/cột đã tồn tại.
    - Bật versioning cho mọi list (vết kiểm toán), tắt attachments, đánh index các cột lọc.
    - -ApplyPermissions: tách quyền theo nguyên tắc "app chỉ đọc, flow mới ghi" (xem docs/05).
    - -SeedData: nạp cấu hình mặc định + tài khoản Admin đầu tiên.
    - -DryRun: chỉ sinh và kiểm tra XML của cột, KHÔNG kết nối SharePoint (dùng để review).

.PARAMETER SiteUrl
    URL site SharePoint, ví dụ https://contoso.sharepoint.com/sites/LabChem

.PARAMETER ClientId
    Client ID của Entra app registration dành cho PnP.PowerShell (bắt buộc với đăng nhập interactive
    kể từ khi PnP bỏ app đa tenant mặc định).

.PARAMETER AdminEmail
    Email Admin đầu tiên, ghi vào LabRoles khi dùng -SeedData.

.PARAMETER ServiceAccountUpn
    Tài khoản dịch vụ sở hữu connection của các flow. Được cấp quyền ghi (không xoá) khi dùng -ApplyPermissions.

.EXAMPLE
    ./New-LabChemLists.ps1 -DryRun
.EXAMPLE
    ./New-LabChemLists.ps1 -SiteUrl https://contoso.sharepoint.com/sites/LabChem -ClientId <guid> `
        -SeedData -AdminEmail admin@contoso.com
.EXAMPLE
    ./New-LabChemLists.ps1 -SiteUrl ... -ClientId <guid> -ApplyPermissions -ServiceAccountUpn svc-labchem@contoso.com
#>
[CmdletBinding()]
param(
    [string]$SiteUrl,
    [string]$ClientId,
    [string]$AdminEmail,
    [string]$ServiceAccountUpn,
    [switch]$ApplyPermissions,
    [switch]$SeedData,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabChem.Schema.ps1')

function ConvertTo-XmlText([string]$Text) { [System.Security.SecurityElement]::Escape($Text) }

function New-FieldXml {
    param([Parameter(Mandatory)]$F)

    $req = if ($F.Required) { 'TRUE' } else { 'FALSE' }
    $idx = if ($F.Indexed) { ' Indexed="TRUE"' } else { '' }
    $id  = '{' + [guid]::NewGuid().ToString() + '}'
    $common = 'ID="{0}" Name="{1}" StaticName="{1}" DisplayName="{2}" Required="{3}"{4}' -f `
        $id, $F.Name, (ConvertTo-XmlText $F.Display), $req, $idx

    switch ($F.Type) {
        'Text' { return "<Field Type=`"Text`" MaxLength=`"255`" $common />" }
        'Note' { return "<Field Type=`"Note`" NumLines=`"6`" RichText=`"FALSE`" $common />" }
        'Number' {
            $extra = ''
            if ($F.Decimals -ge 0)         { $extra += " Decimals=`"$($F.Decimals)`"" }
            if (-not [double]::IsNaN($F.Min)) { $extra += " Min=`"$($F.Min.ToString([cultureinfo]::InvariantCulture))`"" }
            if (-not [double]::IsNaN($F.Max)) { $extra += " Max=`"$($F.Max.ToString([cultureinfo]::InvariantCulture))`"" }
            return "<Field Type=`"Number`"$extra $common />"
        }
        'Boolean' {
            $d = if ($F.Default) { $F.Default } else { '0' }
            return "<Field Type=`"Boolean`" $common><Default>$d</Default></Field>"
        }
        { $_ -in 'Choice', 'MultiChoice' } {
            $opts = ($F.Choices | ForEach-Object { '<CHOICE>' + (ConvertTo-XmlText $_) + '</CHOICE>' }) -join ''
            $def  = if ($F.Default) { '<Default>' + (ConvertTo-XmlText $F.Default) + '</Default>' } else { '' }
            $fmt  = if ($F.Type -eq 'Choice') { 'Type="Choice" Format="Dropdown"' } else { 'Type="MultiChoice"' }
            return "<Field $fmt FillInChoice=`"FALSE`" $common><CHOICES>$opts</CHOICES>$def</Field>"
        }
        'Date'     { return "<Field Type=`"DateTime`" Format=`"DateOnly`" FriendlyDisplayFormat=`"Disabled`" $common />" }
        'DateTime' { return "<Field Type=`"DateTime`" Format=`"DateTime`" FriendlyDisplayFormat=`"Disabled`" $common />" }
        'Url'      { return "<Field Type=`"URL`" Format=`"Hyperlink`" $common />" }
        'User'     { return "<Field Type=`"User`" List=`"UserInfo`" ShowField=`"ImnName`" UserSelectionMode=`"PeopleOnly`" UserSelectionScope=`"0`" Mult=`"FALSE`" $common />" }
    }
}

# ---------------------------------------------------------------- DRY RUN
if ($DryRun) {
    $fieldCount = 0
    foreach ($listName in $LabSchema.Keys) {
        foreach ($f in $LabSchema[$listName].Fields) {
            $xml = New-FieldXml $f
            [void][xml]$xml   # ném lỗi nếu XML sai
            $fieldCount++
            Write-Verbose "$listName.$($f.Name): $xml"
        }
    }
    Write-Host "DryRun OK: $($LabSchema.Count) list, $fieldCount cột, mọi XML hợp lệ." -ForegroundColor Green
    return
}

if (-not $SiteUrl -or -not $ClientId) { throw 'Cần -SiteUrl và -ClientId (hoặc dùng -DryRun).' }

# ---------------------------------------------------------------- CONNECT
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId

# ---------------------------------------------------------------- LISTS
foreach ($listName in $LabSchema.Keys) {
    $spec = $LabSchema[$listName]
    Write-Host "== $listName" -ForegroundColor Cyan

    if (-not (Get-PnPList -Identity $listName -ErrorAction SilentlyContinue)) {
        New-PnPList -Title $listName -Template GenericList -OnQuickLaunch:$false | Out-Null
        Write-Host '   đã tạo list'
    }

    Set-PnPList -Identity $listName -Description $spec.Description `
        -EnableVersioning $true -MajorVersions 500 -EnableAttachments $false | Out-Null

    # Cột Title: đổi tên hiển thị, index, unique
    Set-PnPField -List $listName -Identity 'Title' -Values @{ Title = $spec.TitleDisplay } | Out-Null
    if ($spec.TitleIndexed) {
        $values = @{ Indexed = $true }
        if ($spec.TitleUnique) { $values.EnforceUniqueValues = $true }
        Set-PnPField -List $listName -Identity 'Title' -Values $values | Out-Null
    }

    foreach ($f in $spec.Fields) {
        if (Get-PnPField -List $listName -Identity $f.Name -ErrorAction SilentlyContinue) {
            Write-Host "   bỏ qua $($f.Name) (đã có)"
            continue
        }
        Add-PnPFieldFromXml -List $listName -FieldXml (New-FieldXml $f) | Out-Null
        Write-Host "   + $($f.Name)"
    }

    try {
        Set-PnPView -List $listName -Identity 'All Items' -Fields $spec.ViewFields | Out-Null
    } catch {
        Write-Warning "   Không cập nhật được view mặc định của ${listName}: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- SEED
if ($SeedData) {
    Write-Host '== Seed' -ForegroundColor Cyan
    foreach ($s in $LabSeedSettings) {
        $exists = Get-PnPListItem -List LabSettings -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($s.Key)</Value></Eq></Where></Query></View>"
        if (-not $exists) {
            Add-PnPListItem -List LabSettings -Values @{ Title = $s.Key; Value = $s.Value; Description = $s.Desc } | Out-Null
            Write-Host "   setting $($s.Key)"
        }
    }
    if ($AdminEmail) {
        $mail = $AdminEmail.ToLowerInvariant()
        $exists = Get-PnPListItem -List LabRoles -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$mail</Value></Eq></Where></Query></View>"
        if (-not $exists) {
            Add-PnPListItem -List LabRoles -Values @{ Title = $mail; DisplayName = $mail; Role = 'Admin'; IsActive = $true } | Out-Null
            Write-Host "   admin $mail"
        }
    } else {
        Write-Warning 'Chưa truyền -AdminEmail: LabRoles trống, không ai có quyền Admin trong app.'
    }
}

# ---------------------------------------------------------------- PERMISSIONS
if ($ApplyPermissions) {
    Write-Host '== Permissions' -ForegroundColor Cyan
    if (-not $ServiceAccountUpn) { throw '-ApplyPermissions cần -ServiceAccountUpn (tài khoản sở hữu connection của flow).' }

    # Permission level tuỳ biến: không cho xoá; ledger/audit còn không cho sửa.
    $levels = @{
        'LabChem Writer (No Delete)'  = @{ Clone = 'Contribute'; Exclude = @('DeleteListItems') }
        'LabChem Append Only'         = @{ Clone = 'Contribute'; Exclude = @('EditListItems', 'DeleteListItems') }
    }
    foreach ($name in $levels.Keys) {
        if (-not (Get-PnPRoleDefinition -Identity $name -ErrorAction SilentlyContinue)) {
            Add-PnPRoleDefinition -RoleName $name -Clone $levels[$name].Clone -Exclude $levels[$name].Exclude | Out-Null
            Write-Host "   permission level: $name"
        }
    }

    $groups = 'LabChem Admins', 'LabChem Analysts', 'LabChem Reviewers', 'LabChem Viewers'
    foreach ($g in $groups) {
        if (-not (Get-PnPGroup -Identity $g -ErrorAction SilentlyContinue)) {
            New-PnPGroup -Title $g | Out-Null
            Write-Host "   group: $g"
        }
    }
    $ownerGroup = (Get-PnPGroup -AssociatedOwnerGroup).Title

    # list -> quyền của từng nhóm  (Owner luôn Full Control)
    #   Service = quyền của tài khoản flow; Admin/Reader = các nhóm lab
    $matrix = [ordered]@{
        LabCatalog   = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Contribute'; Readers = 'Read'; Reviewers = 'Read' }
        LabLocations = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Contribute'; Readers = 'Read'; Reviewers = 'Read' }
        LabSettings  = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Contribute'; Readers = 'Read'; Reviewers = 'Read' }
        LabRoles     = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Contribute'; Readers = 'Read'; Reviewers = 'Read' }
        LabLots      = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Read';       Readers = 'Read'; Reviewers = 'Read' }
        LabPreps     = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Read';       Readers = 'Read'; Reviewers = 'Read' }
        LabPrepItems = @{ Service = 'LabChem Append Only';        Admins = 'Read';       Readers = 'Read'; Reviewers = 'Read' }
        LabTestUsage = @{ Service = 'LabChem Append Only';        Admins = 'Read';       Readers = 'Read'; Reviewers = 'Read' }
        LabLedger    = @{ Service = 'LabChem Writer (No Delete)'; Admins = 'Read';       Readers = 'Read'; Reviewers = 'Read' }   # BalanceAfter được cập nhật sau khi tính số dư
        LabAudit     = @{ Service = 'LabChem Append Only';        Admins = 'Read';       Readers = $null;  Reviewers = 'Read' }   # Analyst/Viewer không đọc audit
    }

    foreach ($listName in $matrix.Keys) {
        $m = $matrix[$listName]
        Set-PnPList -Identity $listName -BreakRoleInheritance -CopyRoleAssignments:$false -ClearSubscopes | Out-Null
        Set-PnPListPermission -Identity $listName -Group $ownerGroup -AddRole 'Full Control'
        Set-PnPListPermission -Identity $listName -User $ServiceAccountUpn -AddRole $m.Service
        Set-PnPListPermission -Identity $listName -Group 'LabChem Admins' -AddRole $m.Admins
        Set-PnPListPermission -Identity $listName -Group 'LabChem Reviewers' -AddRole $m.Reviewers
        if ($m.Readers) {
            Set-PnPListPermission -Identity $listName -Group 'LabChem Analysts' -AddRole $m.Readers
            Set-PnPListPermission -Identity $listName -Group 'LabChem Viewers' -AddRole $m.Readers
        }
        Write-Host "   $listName : đã tách quyền"
    }
    Write-Warning 'Hãy thêm người dùng vào các nhóm LabChem * và kiểm tra lại bằng tài khoản thường (xem T-SEC trong docs/05).'
}

Write-Host 'Hoàn tất.' -ForegroundColor Green

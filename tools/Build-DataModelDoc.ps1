# Sinh docs/02-Mo-hinh-du-lieu.md từ sharepoint/LabChem.Schema.ps1
# Chạy: ./tools/Build-DataModelDoc.ps1   (PowerShell 7+)
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
. (Join-Path $Root 'sharepoint\LabChem.Schema.ps1')

$typeVi = @{
    Text = 'Văn bản'; Note = 'Nhiều dòng'; Number = 'Số'; Boolean = 'Có/Không'; Choice = 'Lựa chọn'
    MultiChoice = 'Nhiều lựa chọn'; Date = 'Ngày'; DateTime = 'Ngày giờ'; Url = 'Hyperlink'; User = 'Người'
}
$listTitle = @{
    LabCatalog = '1. LabCatalog — Danh mục hoá chất'; LabLocations = '2. LabLocations — Vị trí lưu trữ'
    LabLots = '3. LabLots — Hoá chất đầu vào (mỗi chai một dòng)'; LabPreps = '4. LabPreps — Hoá chất pha'
    LabPrepItems = '5. LabPrepItems — Thành phần của mỗi lần pha'; LabLedger = '6. LabLedger — Sổ cái xuất/nhập'
    LabTestUsage = '7. LabTestUsage — Liên kết biên bản thử nghiệm'; LabAudit = '8. LabAudit — Nhật ký kiểm toán'
    LabRoles = '9. LabRoles — Phân quyền nghiệp vụ'; LabSettings = '10. LabSettings — Cấu hình'
    LabRequests = '11. LabRequests — Sổ nhận yêu cầu (chống chạy trùng)'
}
function Cell([string]$s) { ($s -replace '\|', '\|') }

$sb = [System.Text.StringBuilder]::new()
foreach ($name in $LabSchema.Keys) {
    $spec = $LabSchema[$name]
    [void]$sb.AppendLine("### $($listTitle[$name])")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($spec.Description)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |')
    [void]$sb.AppendLine('|---|---|---|:-:|:-:|---|---|')
    $titleExtra = if ($spec.TitleUnique) { 'duy nhất' } else { '' }
    [void]$sb.AppendLine("| ``Title`` | $($spec.TitleDisplay) | Văn bản | ✔ | $(if($spec.TitleIndexed){'✔'}) | $titleExtra | |")
    foreach ($f in $spec.Fields) {
        $vals = ''
        if ($f.Choices.Count -gt 0) {
            $vals = ($f.Choices -join ', ')
            if ($f.Default) { $vals += " (mặc định: $($f.Default))" }
        } elseif ($f.Type -eq 'Boolean') {
            $vals = if ($f.Default -eq '1') { 'mặc định: Có' } else { 'mặc định: Không' }
        } elseif ($f.Type -eq 'Number') {
            $bits = @()
            if ($f.Decimals -ge 0) { $bits += "$($f.Decimals) số lẻ" }
            if (-not [double]::IsNaN($f.Min)) { $bits += "≥ $($f.Min)" }
            if (-not [double]::IsNaN($f.Max)) { $bits += "≤ $($f.Max)" }
            $vals = $bits -join ', '
        }
        $row = '| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} |' -f $f.Name, (Cell $f.Display), $typeVi[$f.Type],
            $(if ($f.Required) { '✔' } else { '' }), $(if ($f.Indexed) { '✔' } else { '' }), (Cell $vals), (Cell $f.Note)
        [void]$sb.AppendLine($row)
    }
    [void]$sb.AppendLine()
}
$tables = $sb.ToString()

$seed = ($LabSeedSettings | ForEach-Object {
    $v = if ($_.Value) { '`' + $_.Value + '`' } else { '_(trống)_' }
    '| `' + $_.Key + '` | ' + $v + ' | ' + $_.Desc + ' |'
}) -join "`n"

$doc = @"
# 02 — Mô hình dữ liệu (SharePoint Lists)

> Tài liệu này được **sinh tự động** từ [sharepoint/LabChem.Schema.ps1](../sharepoint/LabChem.Schema.ps1) — đó là nguồn sự thật duy nhất. Muốn đổi cột: sửa file schema, chạy lại script tạo list, chạy ``./tools/Build-DataModelDoc.ps1`` để sinh lại tài liệu. Đừng sửa tay các bảng bên dưới.

## 1. Nguyên tắc thiết kế

1. **Sổ cái là nguồn sự thật cho lượng còn lại.** Mọi biến động ghi thành một dòng ``LabLedger`` (chỉ thêm, không sửa/xoá). ``RemainingQty`` trên ``LabLots``/``LabPreps`` chỉ là bản cache để hiển thị nhanh, được flow tính lại từ sổ cái. Nhờ vậy có thể kiểm toán và tự sửa lỗi lệch số.
2. **App chỉ đọc, flow mới ghi.** Người dùng — kể cả Admin — chỉ có quyền *Read* trên các list; mọi thay đổi (tồn kho, danh mục, vị trí, cấu hình, vai trò) đi qua Power Automate (tài khoản dịch vụ) có kiểm tra phía server và để lại nhật ký. Xem [05](05-Bao-mat-va-Kiem-thu.md).
3. **Không xoá.** Sai thì điều chỉnh/đảo bút toán có lý do; list không cấp quyền Delete cho ai ngoài Owner.
4. **Quan hệ bằng ``ID`` (Number) + mã snapshot (Text), không dùng Lookup column.** Tránh giới hạn 12 cột lookup/view của SharePoint và việc lọc theo lookup không delegable trong Power Apps. Đổi lại, tính toàn vẹn tham chiếu do flow bảo đảm (chỉ flow ghi nên đủ an toàn).
5. **Snapshot tên/hãng/số lô** vào bản ghi con để hồ sơ truy xuất không đổi khi danh mục bị chỉnh sửa về sau (yêu cầu của truy xuất nguồn gốc).
6. **Enum máy dùng khoá tiếng Anh** (``Status``, ``TxnType``...), app ánh xạ sang nhãn tiếng Việt và màu — logic không phụ thuộc chuỗi có dấu.
7. **Mỗi chai/đơn vị vật lý = một dòng ``LabLots`` = một mã QR.** Đăng ký 10 chai cùng lô tạo 10 dòng.
8. **Mọi số lượng lưu theo đơn vị gốc** của hoá chất (g, mL hoặc pcs); đổi đơn vị (mg, kg, µL, L) làm ở giao diện nhập.
9. **Nhật ký đầy đủ, không thể bỏ qua.** Mỗi yêu cầu để lại: một dòng ``LabRequests`` (nhận yêu cầu, duy nhất theo ``RequestId``) → dòng ``LabAudit`` *Started* (ghi **trước** khi làm; ghi không được thì không làm) → một dòng ``LabAudit`` cho **từng đối tượng bị đổi** (kèm giá trị trước/sau và lý do) → dòng kết thúc *Success/Rejected/Error*. Mọi bản ghi do yêu cầu tạo ra mang ``RequestId`` nên dựng lại được toàn bộ dấu vết. Danh tính người thực hiện là **email dạng văn bản** lấy từ phía server, không phải cột Người. Chi tiết: [03 §2.5–2.7](03-Power-Automate.md).

## 2. Sơ đồ quan hệ

``````mermaid
erDiagram
    LabCatalog  ||--o{ LabLots       : "CatalogID"
    LabLocations||--o{ LabLots       : "LocationID"
    LabLocations||--o{ LabPreps      : "LocationID"
    LabPreps    ||--|{ LabPrepItems  : "PrepID (công thức)"
    LabLots     ||--o{ LabPrepItems  : "SourceID, SourceType=Lot"
    LabPreps    ||--o{ LabPrepItems  : "SourceID, SourceType=Prep"
    LabLots     ||--o{ LabLedger     : "ItemID, ItemType=Lot"
    LabPreps    ||--o{ LabLedger     : "ItemID, ItemType=Prep"
    LabLots     ||--o{ LabTestUsage  : "ItemID, ItemType=Lot"
    LabPreps    ||--o{ LabTestUsage  : "ItemID, ItemType=Prep"
    LabRequests ||--o{ LabAudit      : "RequestId (Started … kết thúc)"
    LabRequests ||--o{ LabLedger     : "RequestId (dấu vết)"
    LabRequests ||--o{ LabLots       : "RequestId (dấu vết)"
``````

**Chuỗi truy xuất:** Biên bản thử nghiệm ← ``LabTestUsage`` ← dung dịch pha (``LabPreps``) ← ``LabPrepItems`` ← chai đầu vào (``LabLots``, kèm số lô NSX + COA) — và đệ quy nếu thành phần lại là một dung dịch pha khác (dung dịch gốc → dung dịch làm việc).

## 3. Định danh và nội dung QR

| Đối tượng | Mã | Cách sinh |
|---|---|---|
| Chai đầu vào | ``IN-yy-nnnnn`` (vd ``IN-26-00042``) | ``yy`` = 2 số cuối năm, ``nnnnn`` = SharePoint ``ID`` của item, đệm 5 chữ số |
| Dung dịch pha | ``PC-yy-nnnnn`` (vd ``PC-26-00017``) | tương tự, theo ``ID`` của ``LabPreps`` |

- Flow tạo item với ``Title`` tạm (GUID) rồi cập nhật ``Title`` = mã tính từ ``ID`` → **không có race condition** khi nhiều người đăng ký cùng lúc, không cần bảng bộ đếm.
- ``Title`` đặt *Enforce unique values* nên không thể trùng mã.
- Mã không tái sử dụng, kể cả khi item bị vô hiệu.
- **Nội dung QR** (cấu hình ``QRMode``): ``CodeOnly`` = chỉ chứa mã (ưu tiên: mọi đầu đọc đều hiểu, không lộ thông tin); ``DeepLink`` = ``<AppLink>&code=<mã>`` để quét bằng camera điện thoại là mở thẳng app. Parser trong app hiểu cả hai dạng.

## 4. Quy đổi đơn vị

Lưu ở đơn vị gốc; giao diện cho nhập đơn vị thuận tiện rồi quy đổi trước khi gửi flow.

| Nhập | Đơn vị gốc | Hệ số |
|---|---|---|
| mg | g | 0.001 |
| g | g | 1 |
| kg | g | 1000 |
| µL | mL | 0.001 |
| mL | mL | 1 |
| L | mL | 1000 |
| pcs | pcs | 1 |

Flow luôn kiểm tra ``Unit`` của giao dịch khớp ``Unit`` của đối tượng; không bao giờ tự quy đổi phía server (tránh sai âm thầm).

## 5. Quy tắc nghiệp vụ (flow thực thi phía server)

| Mã | Quy tắc |
|---|---|
| BR-01 | ``RemainingQty`` = Σ ``QtyDelta`` của ``LabLedger`` theo (``ItemType``, ``ItemID``). |
| BR-02 | Số dư không được âm: giao dịch làm số dư < 0 bị từ chối và ghi ``LabAudit`` (Result = Rejected). Dòng sổ cái đã ghi **không bao giờ bị sửa**; sai thì ghi dòng ``Reversal``/``Adjust`` mới. |
| BR-03 | Chỉ được dùng (pha / thử nghiệm) đối tượng có ``Status`` ∈ {Available, InUse}, ``ExpiryDate`` ≥ ngày giao dịch, ``IsVoid`` = false; dung dịch pha còn phải có ``ReviewStatus`` ≠ Rejected. Quarantine / Empty / Expired / Disposed bị chặn. |
| BR-04 | ``Unit`` của giao dịch phải bằng ``Unit`` của đối tượng. |
| BR-05 | Nếu ``EnforcePrepExpiryLimit`` = true: ``ExpiryDate`` dung dịch pha ≤ hạn dùng sớm nhất của các thành phần. |
| BR-06 | Không xoá. Sai sót sửa bằng ``Adjust`` / ``Reversal`` kèm lý do (Admin). ``Void`` chỉ khi đối tượng chưa phát sinh hậu duệ (chưa dùng để pha, chưa gắn biên bản); nếu đã có thì phải ``Dispose``. |
| BR-07 | Mỗi chai một mã; mã không tái sử dụng. |
| BR-08 | Người duyệt (``ReviewedBy``) phải khác người pha (``PreparedBy``). |
| BR-09 | Dùng cho thử nghiệm thì bắt buộc có ``Số biên bản``. |
| BR-10 | ``Status`` tự động: số dư = 0 → Empty; 0 < số dư < ban đầu → InUse; quá hạn → Expired (job hằng ngày). Chai/dung dịch Expired hoặc Empty vẫn tra cứu và truy xuất được. |
| BR-11 | Công thức pha (``LabPrepItems``) bất biến sau khi tạo. |
| BR-12 | Mỗi yêu cầu ghi mang một ``RequestId`` (GUID cho một *ý định* thao tác). Flow **nhận** ``RequestId`` vào ``LabRequests`` (duy nhất) trước khi làm gì; gửi lại cùng ``RequestId`` không bao giờ chạy lại — trả kết quả đã lưu, báo "đang xử lý", hoặc báo "bị gián đoạn" để Admin kiểm tra. Bị từ chối thì app sinh ``RequestId`` mới cho lần thử sau. |
| BR-13 | **Cảnh báo sắp hết (cần mua thêm):** với mỗi hoá chất, ``Tổng tồn`` = Σ ``RemainingQty`` của các chai ``Available``/``InUse``/``Quarantine`` (hàng đã nhập nhưng đang chờ kiểm vẫn tính là có hàng, để không mua trùng). ``Mốc 100%`` = ``ParLevelQty`` nếu có, ngược lại ``PeakQty``. ``Ngưỡng`` = ``LowStockPct`` của hoá chất nếu có, ngược lại ``DefaultLowStockPct``. Cảnh báo khi ``Tổng tồn < Mốc 100% × Ngưỡng / 100`` (kể cả khi đã hết sạch). Riêng từng chai đang dùng: tô vàng khi ``RemainingQty / InitialQty × 100 < Ngưỡng``. |
| BR-14 | **Không có nhật ký thì không có thao tác (fail-closed).** Flow ghi ``LabAudit`` *Started* trước khi thay đổi bất cứ thứ gì; ghi không được thì dừng, không đổi dữ liệu. Mọi yêu cầu — kể cả bị từ chối, của người không có vai trò, hay gặp lỗi — có đủ dòng *Started* và một dòng kết thúc. |
| BR-15 | Mọi bản ghi do flow tạo (``LabLots``, ``LabPreps``, ``LabPrepItems``, ``LabLedger``, ``LabTestUsage``) mang ``RequestId``; sổ cái và nhật ký mang ``ActorEmail`` do server xác định. Mỗi đối tượng bị đổi có dòng ``LabAudit`` riêng; hành động mức *Critical* bắt buộc có lý do và giá trị trước/sau. |
| BR-16 | Danh mục, vị trí, cấu hình và vai trò **chỉ** đổi qua ``LAB-F05``: Admin, có lý do, ghi trước/sau. Không đổi đơn vị gốc của hoá chất đã có chai; không tự hạ quyền chính mình; không bỏ Admin cuối cùng. |
| BR-17 | Nhật ký (``LabAudit``) và sổ cái (``LabLedger``) chỉ thêm: tài khoản flow không có quyền sửa/xoá. Dòng bị sửa, bị xoá hoặc khoảng trống bất thường bị ``LAB-S03`` phát hiện và báo Admin. |

## 6. Cấu hình mặc định (``LabSettings``)

| Khoá | Giá trị | Ý nghĩa |
|---|---|---|
$seed

## 7. Dung lượng và giới hạn SharePoint

- Ước tính tham khảo: 3.000 chai + 2.000 dung dịch/năm → ``LabLedger`` ~ 40.000 dòng/năm. SharePoint chứa tới 30 triệu item/list; ngưỡng 5.000 chỉ chặn truy vấn **không có index** → các cột lọc/sắp xếp đều đã đánh index.
- App đặt *Data row limit* = 2.000 và chỉ dùng hàm delegable (``Filter``, ``StartsWith``, ``LookUp``, ``Sort`` theo cột index). KPI dạng đếm (``CountRows``) chính xác đến 2.000 kết quả/phép lọc; nếu số chai đang quản lý vượt ngưỡng này thì chuyển KPI sang snapshot do flow hằng ngày ghi vào ``LabSettings``.
- Mỗi list tối đa 20 cột index (hiện dùng ≤ 9).
- ``LabAudit`` lớn nhanh nhất: mỗi yêu cầu để lại từ 3 dòng (Started + đối tượng + kết thúc) đến khoảng 25 dòng (nhập 20 chai) → ước tính **50.000–150.000 dòng/năm** cho quy mô vài trăm thao tác/ngày. Vẫn xa giới hạn 30 triệu, nhưng truy vấn trong app phải lọc theo cột có index (``Created``, ``EntityCode``, ``ActorEmail``, ``RequestId``) và sắp theo ``ID``; xuất lưu trữ hằng tháng, lưu trữ theo năm (xem [05 §4](05-Bao-mat-va-Kiem-thu.md)).
- Lưu trữ dài hạn: theo quy định hồ sơ của phòng lab (ví dụ ISO/IEC 17025 thường yêu cầu giữ hồ sơ nhiều năm) — chưa xác nhận với anh, xem câu hỏi mở trong [01](01-Thiet-ke-tong-the.md).

---

## Phụ lục — Chi tiết từng list

$tables
"@

$out = Join-Path $Root 'docs\02-Mo-hinh-du-lieu.md'
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
[System.IO.File]::WriteAllText($out, $doc, [System.Text.UTF8Encoding]::new($false))
"written $out ($($doc.Length) chars)"

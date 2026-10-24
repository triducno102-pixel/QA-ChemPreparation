# 04 — Power Apps (Canvas app): màn hình và công thức

Giao diện tham chiếu: [mockup/index.html](../mockup/index.html). Mở bằng trình duyệt để xem bố cục, màu và cách tương tác dự kiến.

> **Trạng thái:** công thức dưới đây chưa được chạy trong Power Apps Studio (chưa có tenant/environment để kết nối). Khi dựng, hãy dán từng khối, xem App checker và Monitor; các điểm cần xác nhận được gom ở mục 10.

## 1. Thiết lập app

| Mục | Giá trị | Lý do |
|---|---|---|
| Layout | Tablet, 1366 × 768 | Dùng trên PC lab và máy tính bảng |
| Scale to fit / Lock aspect ratio / Lock orientation | **Tắt** cả ba | Để bố cục co giãn theo Container |
| Data row limit | 2000 | Giới hạn tối đa; mọi truy vấn phải delegable |
| Controls | **Modern controls** (Fluent) cho Button, Text input, Combo box, Date picker; **Classic** cho Gallery | Modern có giao diện hiện đại và hỗ trợ accessibility tốt hơn. Control quét camera *Barcode reader* chỉ dùng cho điện thoại/tablet (mục 4.2) |
| Named formulas, Formula-level error management | Bật | Dùng cho `App.Formulas` và `IfError` |
| Data sources | 10 list `Lab*` (SharePoint) + flow `LAB-F01…F04` | `LabAudit` chỉ cần khi có màn Nhật ký |
| Sharing | Chia sẻ cho **nhóm bảo mật** (không phải "Everyone"), quyền *User* | Xem [05](05-Bao-mat-va-Kiem-thu.md) |

## 2. Design tokens — `App.Formulas`

Màu chọn để đạt tương phản ≥ 4.5:1 cho chữ thường trên nền trắng (đã tính: chủ đạo 5.2, chữ phụ 5.1, cảnh báo 5.6, nguy hiểm 5.4, thành công 5.4, thông tin 5.4).

```powerfx
// ---- Màu ----
clrPrimary     = RGBA(11, 122, 117, 1);
clrPrimaryDark = RGBA(8, 90, 86, 1);
clrPrimaryTint = RGBA(230, 244, 243, 1);
clrBg          = RGBA(245, 247, 250, 1);
clrSurface     = RGBA(255, 255, 255, 1);
clrBorder      = RGBA(225, 230, 236, 1);
clrText        = RGBA(27, 36, 48, 1);
clrMuted       = RGBA(97, 112, 130, 1);
clrSuccess     = RGBA(16, 124, 16, 1);
clrWarning     = RGBA(154, 87, 0, 1);
clrDanger      = RGBA(196, 49, 75, 1);
clrInfo        = RGBA(15, 108, 189, 1);

// ---- Hình khối: bo góc 8, khoảng cách theo bậc 4/8/12/16/24, font Segoe UI ----
tkRadius = 8;

// ---- Vai trò & cấu hình ----
fxRole      = Coalesce(LookUp(LabRoles, Title = Lower(User().Email) && IsActive = true, Role.Value), "None");
fxCanWrite  = fxRole = "Admin" || fxRole = "Analyst";
fxCanReview = fxRole = "Admin" || fxRole = "Reviewer";
fxIsAdmin   = fxRole = "Admin";
fxIsPhone   = App.Width < 700;
fxIsCompact = App.Width < 1100;

cfgWarnDays = With({v: IfError(Value(LookUp(LabSettings, Title = "ExpiryWarnDays").Value), 30)}, If(v > 0, v, 30));
cfgLowPct   = With({v: IfError(Value(LookUp(LabSettings, Title = "DefaultLowStockPct").Value), 20)}, If(v > 0, v, 20));   // ngưỡng cảnh báo sắp hết mặc định (%)
cfgLabelBarcode = Coalesce(LookUp(LabSettings, Title = "LabelBarcode").Value, "Code39");
cfgQRBase   = LookUp(LabSettings, Title = "QRBaseUrl").Value;
cfgQRMode   = Coalesce(LookUp(LabSettings, Title = "QRMode").Value, "CodeOnly");
cfgAppLink  = LookUp(LabSettings, Title = "AppLink").Value;
cfgLabName  = Coalesce(LookUp(LabSettings, Title = "LabName").Value, "Phòng thí nghiệm");

// ---- Bảng ánh xạ enum -> nhãn tiếng Việt + màu ----
tblStatus = Table(
    {Key: "Quarantine", Label: "Chờ kiểm",  Tone: clrInfo},
    {Key: "Available",  Label: "Sẵn sàng",  Tone: clrSuccess},
    {Key: "InUse",      Label: "Đang dùng", Tone: clrPrimary},
    {Key: "Empty",      Label: "Đã hết",    Tone: clrMuted},
    {Key: "Expired",    Label: "Hết hạn",   Tone: clrDanger},
    {Key: "Disposed",   Label: "Đã huỷ",    Tone: clrMuted}
);
tblTxn = Table(
    {Key: "Receive",    Label: "Nhập kho"},        {Key: "PrepCreate", Label: "Tạo dung dịch"},
    {Key: "PrepUse",    Label: "Dùng để pha"},     {Key: "TestUse",    Label: "Dùng thử nghiệm"},
    {Key: "Adjust",     Label: "Điều chỉnh"},      {Key: "Dispose",    Label: "Huỷ bỏ"},
    {Key: "Reversal",   Label: "Đảo bút toán"}
);
tblUnits = Table(
    {Unit: "mg", Base: "g",   Factor: 0.001}, {Unit: "g",  Base: "g",   Factor: 1}, {Unit: "kg", Base: "g",   Factor: 1000},
    {Unit: "µL", Base: "mL",  Factor: 0.001}, {Unit: "mL", Base: "mL",  Factor: 1}, {Unit: "L",  Base: "mL",  Factor: 1000},
    {Unit: "pcs", Base: "pcs", Factor: 1}
);
```

**Quy tắc màu hạn dùng** (dùng ở mọi nơi hiển thị `ExpiryDate`; luôn kèm chữ, không chỉ dựa vào màu):

```powerfx
If(IsBlank(ThisItem.ExpiryDate), clrMuted,
   ThisItem.ExpiryDate < Today(), clrDanger,
   ThisItem.ExpiryDate <= DateAdd(Today(), cfgWarnDays, TimeUnit.Days), clrWarning,
   clrSuccess)
```

## 3. Khung giao diện và điều hướng

```
┌───────────────────────────────────────────────────────────────┐
│ Header 56px: logo • tên phòng lab (cfgLabName) • ô quét nhanh • người dùng/vai trò │
├──────────┬────────────────────────────────────────────────────┤
│ Nav rail │  Nội dung (Container dọc, padding 24, nền clrBg)   │
│ 240px    │                                                    │
│ (72px khi│                                                    │
│ fxIsCompact)                                                  │
└──────────┴────────────────────────────────────────────────────┘
        Điện thoại (fxIsPhone): nav rail → thanh điều hướng dưới đáy 5 mục
```

- Mục nav: **Trang chủ · Quét mã · Tồn kho · Nhập hoá chất · Pha chế · Truy xuất · Quản trị** (Quản trị chỉ hiện khi `fxIsAdmin`; Nhập/Pha chế chỉ hiện khi `fxCanWrite`).
- Mỗi màn hình dựng bằng **Container (auto-layout)**; không đặt `X/Y` thủ công. Nav rail, header, badge trạng thái, tile KPI, ô nhập mã làm **component** dùng chung (mục 8).
- `App.StartScreen = If(fxRole = "None", scrNoAccess, scrHome)`.

```powerfx
// App.OnStart  (giữ tối thiểu; logic phụ thuộc dữ liệu đã nằm ở named formulas)
Set(varDeepLink, Param("code"));   // QR dạng DeepLink: ...&code=PC-26-00017
Set(varReqId, GUID());             // RequestId cho thao tác ghi hiện hành
Set(varBusy, false);
```

## 4. Các màn hình

### 4.1 `scrHome` — Trang chủ

Mục đích: nhìn nhanh tình trạng phòng lab và đi tới việc cần làm.

- **4 tile KPI:** Chai đang quản lý · Sắp hết hạn (≤ `cfgWarnDays`) · Đã quá hạn còn tồn · **Cần mua thêm** (dưới ngưỡng %). Bấm vào tile mở `scrInventory` với bộ lọc tương ứng.
- **Lối tắt:** Quét mã · Nhập hoá chất · Pha chế · Ghi nhận sử dụng.
- **Danh sách cảnh báo** và **hoạt động gần đây**.

```powerfx
// scrHome.OnVisible
Concurrent(
    ClearCollect(colCatalog,   Filter(LabCatalog,   IsActive = true)),
    ClearCollect(colLocations, Filter(LabLocations, IsActive = true)),
    ClearCollect(colActive,    Filter(LabLots, Status.Value = "Available" || Status.Value = "InUse" || Status.Value = "Quarantine"))   // gồm hàng chờ kiểm: vẫn tính là có hàng
);
// Mỗi hoá chất đang dùng trong danh mục -> tổng tồn, mốc 100%, ngưỡng %, cờ cần mua thêm (BR-13).
// Dựng từ danh mục (không dựng từ danh sách chai) để hoá chất đã hết sạch vẫn xuất hiện với Total = 0.
ClearCollect(
    colStock,
    ForAll(
        colCatalog As cat,
        With(
            {rows: Filter(colActive, CatalogID = cat.ID)},
            With(
                {
                    total: Sum(rows, RemainingQty),
                    ref:   If(cat.ParLevelQty > 0, cat.ParLevelQty, Coalesce(cat.PeakQty, 0)),
                    pct:   If(cat.LowStockPct > 0, cat.LowStockPct, cfgLowPct)
                },
                {
                    CatalogID: cat.ID, Name: cat.Title, Unit: cat.BaseUnit.Value,
                    Bottles: CountRows(rows), Total: total, Ref: ref, Pct: pct,
                    PctOfRef: If(ref > 0, Round(total / ref * 100, 0), Blank()),
                    Low: ref > 0 && total < ref * pct / 100
                }
            )
        )
    )
);
// Mở thẳng một mã nếu app được bật bằng QR dạng DeepLink
If(!IsBlank(varDeepLink),
    Set(varScanRaw, varDeepLink); Set(varDeepLink, Blank()); Navigate(scrScan, ScreenTransition.None));
```

```powerfx
// Giá trị tile
kpiActive   = CountRows(colActive)
kpiExpiring = CountRows(Filter(colActive, ExpiryDate >= Today() && ExpiryDate <= DateAdd(Today(), cfgWarnDays, TimeUnit.Days)))
kpiExpired  = CountRows(Filter(colActive, ExpiryDate < Today()))     // đã quá hạn nhưng job S01 chưa đánh dấu
kpiLow      = CountRows(Filter(colStock, Low))      // Cần mua thêm

// Hoạt động gần đây (Items của Gallery)
FirstN(Sort(LabLedger, Created, SortOrder.Descending), 8)
```

> `colActive` giới hạn 2000 dòng. Nếu số chai đang quản lý vượt ngưỡng, KPI sẽ thiếu — chuyển sang snapshot do `LAB-S01` ghi (xem [02](02-Mo-hinh-du-lieu.md) mục 7).

### 4.2 `scrScan` — Quét mã

**Máy quét Zebra cầm tay (loại "đưa vào kêu tít" như ở siêu thị) không có camera và không gửi hình ảnh vào app.** Nó hoạt động như **bàn phím**: mỗi lần quét, máy "gõ" nội dung mã vào ô đang được chọn (focus), thường kèm phím Enter. Với Power Apps, đó chỉ là một ô nhập văn bản — nên **không dùng control camera** cho trường hợp này.

| Cách quét | Thiết bị | Control trong app | Ghi chú |
|---|---|---|---|
| **Máy quét cầm tay (cách chính)** | Zebra USB hoặc Bluetooth nối với PC/laptop/tablet | Text input + Timer | Chạy cả khi mở app bằng trình duyệt; không cần quyền camera; không có khung hình |
| Máy Zebra Android (dòng TC/MC, có đầu quét tích hợp) | Nút quét trên thân máy | Text input + cấu hình DataWedge | Xem "Máy Zebra Android" bên dưới |
| Camera điện thoại / tablet (phụ) | Android, iOS, ứng dụng Power Apps for Windows | **Barcode reader** | **Không hoạt động trong trình duyệt** (theo tài liệu Microsoft). Là nút bấm mở màn hình quét của hệ điều hành |

```powerfx
// ---- Máy quét cầm tay ----
// txtScan : Text input, giữ focus khi vào màn hình, gợi ý "Sẵn sàng quét…"
// tmrScan : Timer (Duration = 300, Repeat = true, AutoStart = true, Visible = false)

// scrScan.OnVisible
Reset(txtScan); SetFocus(txtScan);
If(!IsBlank(varScanRaw), Select(btnResolve));        // mã đến từ QR DeepLink hoặc camera

// tmrScan.OnTimerEnd — cứ 0,3 giây xem ô nhập; thấy một mã hợp lệ là xử lý ngay
If(
    !IsBlank(Match(txtScan.Value, "(IN|PC)-\d{2}-\d{5}", MatchOptions.IgnoreCase).FullMatch),
    Set(varScanRaw, txtScan.Value); Select(btnResolve)
);

// btnResolve.OnSelect — hiểu "PC-26-00017", "pc-26-00017" + ký tự xuống dòng, hoặc "https://…&code=PC-26-00017"
With(
    {raw: Coalesce(varScanRaw, txtScan.Value)},
    With(
        {m: Match(raw, "(IN|PC)-\d{2}-\d{5}", MatchOptions.IgnoreCase)},
        If(
            !IsBlank(m.FullMatch),
            Navigate(scrDetail, ScreenTransition.None, {pCode: Upper(m.FullMatch)}),
            Notify("Không nhận ra mã: " & Left(raw, 40), NotificationType.Warning)
        )
    )
);
Set(varScanRaw, Blank()); Reset(txtScan); SetFocus(txtScan);

// ---- Camera (chỉ hiện trên màn hình nhỏ) ----
// BarcodeReader1.Visible = fxIsCompact
// BarcodeReader1.OnScan
Set(varScanRaw, First(BarcodeReader1.Barcodes).Value); Select(btnResolve);
```

**Vì sao dùng Timer thay vì `OnChange`:** máy quét gõ cả mã trong chưa đến một giây. Người dùng cộng đồng Power Apps từng báo `OnChange` của ô nhập cho kết quả không ổn định khi nhập bằng máy quét USB. Timer đọc thẳng nội dung ô nhập và bắt mẫu `IN-yy-nnnnn`/`PC-yy-nnnnn`, nên đúng cả khi máy có hay không có phím Enter. Nút **Tìm** vẫn có cho người gõ tay.

**Cấu hình máy Zebra (làm một lần, theo sách "Product Reference Guide" đúng model):**

1. **Giao tiếp:** USB HID Keyboard (quét mã cấu hình tương ứng). Máy Bluetooth: ghép đôi ở chế độ HID.
2. **Hậu tố:** bật "Add Enter Key" (nên có cho các ô nhập khác trong app, dù màn Quét không cần).
3. **Loại mã:** bật Code 39 / Code 128 (thường bật sẵn). **QR chỉ đọc được bởi máy 2D (imager)** — xem bảng bên dưới.
4. **Windows:** để bàn phím tiếng Anh (tắt Unikey/Telex) khi quét, tránh bộ gõ biến đổi ký tự.

| Model Zebra | Loại | Đọc được |
|---|---|---|
| LS2208 và các máy laser tương tự | 1D (laser) | Mã vạch tuyến tính (Code 39/128…), **không đọc QR** |
| DS2208, DS2278 và các máy imager | 2D | Mã vạch tuyến tính **và** QR |

→ Vì chưa biết model, **nhãn in cả QR lẫn mã vạch Code 39** (mục 4.9). Máy 1D đọc mã vạch, máy 2D và điện thoại đọc QR hoặc mã vạch.

**Máy Zebra Android (DataWedge):** tạo profile gắn với ứng dụng Power Apps, bật *Keystroke output*, đặt hậu tố Enter. Một người dùng cộng đồng báo đã dùng cấu hình gửi phím Tab trước/sau mã kèm ô nhập ẩn để bàn phím ảo không bật lên — cách này em chưa tự kiểm chứng.

Dưới ô quét hiển thị **10 mã vừa quét** (`colRecentScans`) để mở lại nhanh.

### 4.3 `scrInventory` — Theo dõi lượng còn lại

- Hai tab: **Hoá chất đầu vào** (`LabLots`) và **Dung dịch pha** (`LabPreps`).
- Ô tìm (mã, tên, số lô), chip lọc theo **Trạng thái**, **Sắp hết hạn**, **Vị trí**.
- Mỗi dòng: mã (in đậm) · tên · số lô/nồng độ · vị trí · hạn dùng (màu theo quy tắc) · **thanh còn lại** (`còn/ban đầu`, kèm số "250 / 500 mL") · badge trạng thái.
- Chế độ **Gộp theo hoá chất** (từ `colStock`): tổng lượng còn của mọi chai, số chai, **% còn lại so với lượng tồn chuẩn** (thanh tiến độ) và nhãn **Cần mua thêm** khi dưới ngưỡng % (BR-13).

```powerfx
// Gallery hoá chất đầu vào — .Items  (phải không có cảnh báo delegation)
Sort(
    Filter(
        LabLots,
        IsBlank(varStatusFilter) || Status.Value = varStatusFilter,
        IsBlank(txtSearch.Value) || StartsWith(Title, txtSearch.Value) || StartsWith(ChemName, txtSearch.Value) || StartsWith(MfgLot, txtSearch.Value)
    ),
    ExpiryDate, SortOrder.Ascending
)

// Thanh còn lại — Rectangle.Width
Parent.Width * If(ThisItem.InitialQty > 0, Min(1, ThisItem.RemainingQty / ThisItem.InitialQty), 0)

// Nhãn trạng thái
LookUp(tblStatus, Key = ThisItem.Status.Value).Label

// Thanh còn lại của từng chai: vàng khi dưới ngưỡng % của hoá chất đó (mặc định cfgLowPct)
If(
    ThisItem.InitialQty > 0 && ThisItem.RemainingQty / ThisItem.InitialQty * 100 <
        With({c: LookUp(colCatalog, ID = ThisItem.CatalogID)}, If(c.LowStockPct > 0, c.LowStockPct, cfgLowPct)),
    clrWarning, clrPrimary
)

// Tab "Gộp theo hoá chất" — Items của Gallery, hoá chất cần mua đứng đầu
SortByColumns(colStock, "Low", SortOrder.Descending, "Name", SortOrder.Ascending)

// Thanh % so với lượng chuẩn — Rectangle.Width và màu
Parent.Width * Min(1, Coalesce(ThisItem.PctOfRef, 100) / 100)
If(ThisItem.Low, clrDanger, clrPrimary)
```

Bấm một dòng: `Navigate(scrDetail, ScreenTransition.None, {pCode: ThisItem.Title})`.

### 4.4 `scrDetail` — Chi tiết, lịch sử, thao tác

Nhận `pCode`. Chuẩn hoá hai loại đối tượng về cùng một record để giao diện dùng chung:

```powerfx
// scrDetail.OnVisible
Set(varLot,  If(Left(pCode, 3) = "IN-", LookUp(LabLots,  Title = pCode), Blank()));
Set(varPrep, If(Left(pCode, 3) = "PC-", LookUp(LabPreps, Title = pCode), Blank()));
Set(
    varView,
    If(
        !IsBlank(varLot),
        {Type: "Lot", ID: varLot.ID, Code: varLot.Title, Name: varLot.ChemName, Sub: "Số lô NSX: " & varLot.MfgLot,
         Remaining: varLot.RemainingQty, Initial: varLot.InitialQty, Unit: varLot.Unit.Value, Status: varLot.Status.Value,
         Expiry: varLot.ExpiryDate, Location: varLot.LocationName},
        !IsBlank(varPrep),
        {Type: "Prep", ID: varPrep.ID, Code: varPrep.Title, Name: varPrep.PrepName, Sub: varPrep.Concentration,
         Remaining: varPrep.RemainingQty, Initial: varPrep.FinalQty, Unit: varPrep.Unit.Value, Status: varPrep.Status.Value,
         Expiry: varPrep.ExpiryDate, Location: varPrep.LocationName},
        Blank()
    )
);
If(IsBlank(varView), Notify("Không tìm thấy " & pCode, NotificationType.Error); Back());
Set(varReqId, GUID());
```

Bố cục: cột trái = thẻ thông tin + **QR** + đồng hồ lượng còn lại; cột phải = tab **Lịch sử** / **Công thức** (chỉ Prep) / **Biên bản liên quan**.

```powerfx
// Lịch sử xuất/nhập (Items)
Sort(Filter(LabLedger, ItemType.Value = varView.Type && ItemID = varView.ID), Created, SortOrder.Descending)

// Công thức (Prep)
Filter(LabPrepItems, PrepID = varView.ID)

// Biên bản liên quan
Filter(LabTestUsage, ItemType.Value = varView.Type && ItemID = varView.ID)

// Ảnh QR (Image.Image)
cfgQRBase & EncodeUrl(If(cfgQRMode = "DeepLink" && !IsBlank(cfgAppLink), cfgAppLink & "&code=" & varView.Code, varView.Code))
```

Nút (hiện theo vai trò và trạng thái):

| Nút | Điều kiện hiện | Hành động |
|---|---|---|
| Ghi nhận sử dụng | `fxCanWrite` và trạng thái `Available`/`InUse` | `Navigate(scrUsage, …, {pPreload: varView})` |
| In nhãn | luôn | `Navigate(scrLabel, …, {pCodes: Table({Code: varView.Code})})` |
| Truy xuất | luôn | `Navigate(scrTrace, …, {pCode: varView.Code})` |
| Duyệt / Từ chối (Prep) | `fxCanReview` và `ReviewStatus = Pending` | gọi `LAB-F04` `Review` |
| Release (Lot Quarantine) | `fxCanReview` | gọi `LAB-F04` `Release` |
| Điều chỉnh / Huỷ bỏ / Vô hiệu | `fxIsAdmin` | hộp thoại bắt buộc nhập lý do → `LAB-F04` |

Mẫu gọi flow (dùng chung cho mọi thao tác ghi). `requestId` **sinh một lần** khi mở màn hình/biểu mẫu, không sinh lại trong lúc thử lại — đó là cơ chế chống ghi trùng:

```powerfx
Set(varBusy, true);
Set(varRes, Blank());
IfError(
    Set(varRes, 'LAB-F04 AdminAction'.Run(JSON(
        {requestId: varReqId, action: "Adjust", itemType: varView.Type, itemId: varView.ID,
         newQty: Value(txtNewQty.Value), decision: "", reason: Trim(txtReason.Value)},
        JSONFormat.Compact))),
    Notify("Không kết nối được máy chủ. Hãy thử lại — thao tác sẽ không bị ghi trùng.", NotificationType.Error)
);
Set(varBusy, false);
If(!IsBlank(varRes) && varRes.success,
    Notify(varRes.message, NotificationType.Success); Set(varReqId, GUID()); Navigate(scrDetail, ScreenTransition.None, {pCode: varView.Code}),
    !IsBlank(varRes), Notify(varRes.message, NotificationType.Error))
```

### 4.5 `scrLotRegister` — Đăng ký hoá chất đầu vào

Một cột, chia 3 thẻ; bên phải (màn rộng) là thẻ **Tóm tắt** (tên, số chai, tổng lượng, hạn dùng, cảnh báo) cố định.

| Thẻ | Trường |
|---|---|
| Hoá chất | `cmbChem` (tìm theo tên/CAS từ `colCatalog`), đơn vị gốc hiển thị tự động |
| Nguồn gốc | Số lô NSX, Hãng SX, Nhà cung cấp, Ngày nhận (mặc định hôm nay), Ngày SX, **Hạn dùng** |
| Lượng & vị trí | Lượng **mỗi chai** + đơn vị nhập, **Số chai**, Vị trí (`colLocations`), Link COA, Ghi chú |

```powerfx
// cmbChem.Items
Filter(colCatalog, IsBlank(Self.SearchText) || StartsWith(Title, Self.SearchText) || StartsWith(CasNumber, Self.SearchText))

// ddUnitInput.Items  (chỉ đơn vị cùng nhóm với đơn vị gốc)
Filter(tblUnits, Base = cmbChem.Selected.BaseUnit.Value)

// Lượng mỗi chai quy về đơn vị gốc (nhãn tóm tắt)
Value(txtQty.Value) * LookUp(tblUnits, Unit = ddUnitInput.Selected.Unit).Factor

// Thông báo lỗi ngay dưới ô (ví dụ hạn dùng)
If(!IsBlank(dpExpiry.SelectedDate) && dpExpiry.SelectedDate <= dpReceived.SelectedDate, "Hạn dùng phải sau ngày nhận", "")

// btnSubmit.DisplayMode
If(!varBusy && !IsBlank(cmbChem.Selected) && IsNumeric(txtQty.Value) && Value(txtQty.Value) > 0
   && !IsBlank(dpExpiry.SelectedDate) && dpExpiry.SelectedDate > dpReceived.SelectedDate
   && numBottles.Value >= 1 && numBottles.Value <= 20,
   DisplayMode.Edit, DisplayMode.Disabled)
```

```powerfx
// btnSubmit.OnSelect
Set(varBusy, true);
Set(varRes, Blank());
IfError(
    Set(varRes, 'LAB-F01 RegisterIncoming'.Run(JSON(
        {
            requestId:    varReqId,
            catalogId:    cmbChem.Selected.ID,
            mfgLot:       Trim(txtMfgLot.Value),
            manufacturer: Trim(txtManufacturer.Value),
            supplier:     Trim(txtSupplier.Value),
            receivedDate: Text(dpReceived.SelectedDate, "yyyy-mm-dd", "en-US"),
            mfgDate:      If(IsBlank(dpMfg.SelectedDate), "", Text(dpMfg.SelectedDate, "yyyy-mm-dd", "en-US")),
            expiryDate:   Text(dpExpiry.SelectedDate, "yyyy-mm-dd", "en-US"),
            qty:          Value(txtQty.Value) * LookUp(tblUnits, Unit = ddUnitInput.Selected.Unit).Factor,
            unit:         cmbChem.Selected.BaseUnit.Value,
            bottleCount:  numBottles.Value,
            locationId:   Coalesce(cmbLocation.Selected.ID, 0),
            coaLink:      Trim(txtCoa.Value),
            note:         Trim(txtNote.Value)
        },
        JSONFormat.Compact))),
    Notify("Không kết nối được máy chủ. Dữ liệu đã nhập vẫn còn, hãy bấm lại.", NotificationType.Error)
);
Set(varBusy, false);
If(
    !IsBlank(varRes) && varRes.success,
    Set(varReqId, GUID());
    Navigate(scrLabel, ScreenTransition.None, {pCodes: ForAll(Split(varRes.codes, ","), {Code: Value})}),
    !IsBlank(varRes),
    Notify(varRes.message, NotificationType.Error)
)
```

Sau khi thành công đi thẳng sang `scrLabel` để in nhãn dán lên từng chai (đây là lúc mã QR ra đời).

### 4.6 `scrPrepRegister` — Đăng ký pha chế (3 bước)

Thanh tiến trình **1 Thông tin → 2 Thành phần → 3 Xác nhận**, biến `varStep`.

**Bước 1 — Thông tin dung dịch:** tên, loại, nồng độ, SOP, cách pha, ngày pha, hạn dùng, **thể tích/lượng sau pha + đơn vị**, vị trí, điều kiện bảo quản.

**Bước 2 — Thành phần:** ô nhập mã (quét hoặc gõ, component `cmpCodeInput`) và nút "Thêm từ tồn kho" (tìm theo tên). Mỗi thành phần là một dòng với: mã · tên · "còn lại" · **ô nhập lượng + đơn vị** · vai trò · thông báo lỗi tại chỗ. Lỗi hiện ngay khi gõ — người dùng không phải đợi flow mới biết.

```powerfx
// Thêm thành phần (varAddCode đã chuẩn hoá như btnResolve)
If(
    varAddCode in colIng.Code,
    Notify("Thành phần này đã có trong danh sách", NotificationType.Warning),
    Left(varAddCode, 3) = "IN-",
    With({s: LookUp(LabLots, Title = varAddCode)},
        If(IsBlank(s), Notify("Không tìm thấy " & varAddCode, NotificationType.Error),
           Collect(colIng, {Type: "Lot", ID: s.ID, Code: s.Title, Name: s.ChemName, Detail: "Lô " & s.MfgLot,
                            Unit: s.Unit.Value, Avail: s.RemainingQty, Expiry: s.ExpiryDate, Status: s.Status.Value,
                            InQty: 0, InUnit: s.Unit.Value, Qty: 0, Role: "Chất tan"}))),
    Left(varAddCode, 3) = "PC-",
    With({s: LookUp(LabPreps, Title = varAddCode)},
        If(IsBlank(s), Notify("Không tìm thấy " & varAddCode, NotificationType.Error),
           Collect(colIng, {Type: "Prep", ID: s.ID, Code: s.Title, Name: s.PrepName, Detail: s.Concentration,
                            Unit: s.Unit.Value, Avail: s.RemainingQty, Expiry: s.ExpiryDate, Status: s.Status.Value,
                            InQty: 0, InUnit: s.Unit.Value, Qty: 0, Role: "Chất tan"}))),
    Notify("Mã không hợp lệ", NotificationType.Warning)
)

// Ô nhập lượng và ô đơn vị trong dòng (cùng một OnChange)
UpdateIf(colIng, Code = ThisItem.Code,
    {InQty: Value(txtRowQty.Value), InUnit: ddRowUnit.Selected.Unit,
     Qty: Value(txtRowQty.Value) * LookUp(tblUnits, Unit = ddRowUnit.Selected.Unit).Factor})

// Lỗi tại chỗ của một dòng (nhãn đỏ dưới dòng)
If(
    !(ThisItem.Status in ["Available", "InUse"]), "Không ở trạng thái sử dụng được",
    ThisItem.Expiry < Today(), "Đã hết hạn",
    ThisItem.Qty <= 0, "Nhập lượng",
    ThisItem.Qty > ThisItem.Avail, "Vượt lượng còn lại (" & ThisItem.Avail & " " & ThisItem.Unit & ")",
    ""
)

// Hạn dùng tối đa cho dung dịch (hiển thị gợi ý ở bước 1 & 3)
First(Sort(colIng, Expiry, SortOrder.Ascending)).Expiry

// Cho phép sang bước 3
CountRows(colIng) > 0 &&
CountRows(Filter(colIng, Qty <= 0 || Qty > Avail || Expiry < Today() || !(Status in ["Available", "InUse"]))) = 0
```

**Bước 3 — Xác nhận:** bảng công thức, cảnh báo (hạn dùng vượt hạn thành phần, thành phần sắp hết hạn), nút **Lưu & in nhãn**.

```powerfx
// btnSavePrep.OnSelect (rút gọn phần kiểm tra, giống 4.5)
Set(varRes, 'LAB-F02 CreatePreparation'.Run(JSON(
    {
        requestId: varReqId, prepName: Trim(txtPrepName.Value), prepType: ddPrepType.Selected.Value,
        concentration: Trim(txtConc.Value), sopRef: Trim(txtSop.Value), procedure: Trim(txtProc.Value),
        prepDate: Text(dpPrep.SelectedDate, "yyyy-mm-dd", "en-US"), expiryDate: Text(dpPrepExpiry.SelectedDate, "yyyy-mm-dd", "en-US"),
        finalQty: Value(txtFinal.Value) * LookUp(tblUnits, Unit = ddFinalUnit.Selected.Unit).Factor,
        unit: LookUp(tblUnits, Unit = ddFinalUnit.Selected.Unit).Base,
        locationId: Coalesce(cmbPrepLoc.Selected.ID, 0), storageCondition: ddStorage.Selected.Value, note: Trim(txtPrepNote.Value),
        items: ForAll(colIng, {sourceType: Type, sourceId: ID, qty: Qty, role: Role})
    }, JSONFormat.Compact)));
// thành công: Clear(colIng); Set(varStep, 1); Set(varReqId, GUID()); Navigate(scrLabel, …, {pCodes: Table({Code: varRes.codes})})
```

### 4.7 `scrUsage` — Ghi nhận sử dụng & gắn biên bản thử nghiệm

Dùng khi chạy thử nghiệm: nhập **Số biên bản**, link biên bản, phép thử, mã mẫu, thời điểm; rồi quét/nhập một hoặc nhiều mã hoá chất (dung dịch pha hoặc chai) và lượng đã dùng cho mỗi mã. Công tắc "Không gắn biên bản" chuyển `purpose = "Other"` và bắt buộc nhập lý do.

- Danh sách dòng: `colUse` (giống `colIng`, khác ở chỗ không có `Role`).
- Gọi `'LAB-F03 RecordUsage'.Run(JSON({requestId, purpose, reportNo, reportUrl, testName, sampleCode, usedDate, note, lines: ForAll(colUse, {itemType: Type, itemId: ID, qty: Qty})}, JSONFormat.Compact))`.
- Gợi ý nhập nhanh: sau khi quét một mã từ `scrDetail`, màn này mở sẵn dòng đầu (`pPreload`).

### 4.8 `scrTrace` — Truy xuất (yêu cầu 4)

Một ô nhập mã (quét/gõ) và hai chế độ tự nhận theo tiền tố:

- **`PC-…` (dung dịch pha):** thông tin dung dịch → **Nguồn gốc** (cây công thức: dung dịch ← chai đầu vào [số lô NSX, COA]; nếu thành phần là dung dịch pha khác thì mở rộng tiếp, tối đa 3 cấp) → **Biên bản thử nghiệm đã dùng** (số biên bản, phép thử, ngày, lượng, người làm, nút mở biên bản) → **Dùng tiếp cho** (dung dịch hậu duệ và biên bản của chúng).
- **`IN-…` (chai đầu vào):** truy xuôi — những dung dịch được pha từ chai này, và mọi biên bản liên quan (kể cả qua dung dịch hậu duệ). Phục vụ tình huống thu hồi/cảnh báo chất lượng theo số lô.

```powerfx
// Dung dịch pha: nguồn gốc (tối đa 3 cấp)
Set(varTPrep, LookUp(LabPreps, Title = varTraceCode));
ClearCollect(colUp, AddColumns(Filter(LabPrepItems, PrepID = varTPrep.ID), "Level", 1, "ParentCode", varTPrep.Title));
ForAll(Filter(colUp, Level = 1 && SourceType.Value = "Prep") As p,
    Collect(colUp, AddColumns(Filter(LabPrepItems, PrepID = p.SourceID), "Level", 2, "ParentCode", p.SourceCode)));
ForAll(Filter(colUp, Level = 2 && SourceType.Value = "Prep") As p,
    Collect(colUp, AddColumns(Filter(LabPrepItems, PrepID = p.SourceID), "Level", 3, "ParentCode", p.SourceCode)));

// Biên bản trực tiếp + biên bản qua dung dịch hậu duệ
ClearCollect(colReports, AddColumns(Filter(LabTestUsage, ItemType.Value = "Prep" && ItemID = varTPrep.ID), "Via", ""));
ClearCollect(colDesc, AddColumns(Filter(LabPrepItems, SourceType.Value = "Prep" && SourceID = varTPrep.ID), "Level", 1));
ForAll(Filter(colDesc, Level = 1) As d,
    Collect(colDesc, AddColumns(Filter(LabPrepItems, SourceType.Value = "Prep" && SourceID = d.PrepID), "Level", 2)));
ForAll(colDesc As d,
    Collect(colReports, AddColumns(Filter(LabTestUsage, ItemType.Value = "Prep" && ItemID = d.PrepID), "Via", d.Title)));
```

```powerfx
// Chai đầu vào: truy xuôi
Set(varTLot, LookUp(LabLots, Title = varTraceCode));
ClearCollect(colDesc, AddColumns(Filter(LabPrepItems, SourceType.Value = "Lot" && SourceID = varTLot.ID), "Level", 1));
ForAll(Filter(colDesc, Level = 1) As d,
    Collect(colDesc, AddColumns(Filter(LabPrepItems, SourceType.Value = "Prep" && SourceID = d.PrepID), "Level", 2)));
ForAll(Filter(colDesc, Level = 2) As d,
    Collect(colDesc, AddColumns(Filter(LabPrepItems, SourceType.Value = "Prep" && SourceID = d.PrepID), "Level", 3)));
ClearCollect(colReports, AddColumns(Filter(LabTestUsage, ItemType.Value = "Lot" && ItemID = varTLot.ID), "Via", ""));
ForAll(colDesc As d,
    Collect(colReports, AddColumns(Filter(LabTestUsage, ItemType.Value = "Prep" && ItemID = d.PrepID), "Via", d.Title)));
```

```powerfx
// Nút mở biên bản (chỉ https, đã được flow kiểm tra khi ghi — kiểm tra lần nữa khi mở)
If(StartsWith(ThisItem.ReportUrl, "https://"), Launch(ThisItem.ReportUrl), Notify("Liên kết biên bản không hợp lệ", NotificationType.Warning))
```

Nút **Xuất báo cáo truy xuất** (PDF/Excel) là giai đoạn 2.

### 4.9 `scrLabel` — In nhãn

Nhận `pCodes` (bảng `{Code}`). Mỗi nhãn: **QR + mã vạch Code 39 + mã (chữ lớn, đọc được bằng mắt) + tên + số lô/nồng độ + hạn dùng + vị trí**. Mã vạch Code 39 để máy quét 1D (laser) đọc được; có thể tắt bằng `LabelBarcode = None`. Kích thước nhãn đặt bằng biến để đổi theo máy in.

```powerfx
// scrLabel.OnVisible — chuẩn hoá dữ liệu nhãn
ClearCollect(
    colLabels,
    ForAll(
        pCodes As c,
        If(
            Left(c.Code, 3) = "IN-",
            With({s: LookUp(LabLots, Title = c.Code)},
                {Code: s.Title, Line1: s.ChemName, Line2: "Lô " & s.MfgLot,
                 Line3: "HSD " & Text(s.ExpiryDate, "dd/mm/yyyy"), Loc: s.LocationName}),
            With({s: LookUp(LabPreps, Title = c.Code)},
                {Code: s.Title, Line1: s.PrepName & " " & s.Concentration, Line2: "Pha " & Text(s.PrepDate, "dd/mm/yyyy"),
                 Line3: "HSD " & Text(s.ExpiryDate, "dd/mm/yyyy"), Loc: s.LocationName})
        )
    )
);

// btnPrint.OnSelect
Print()
```

**Mã vạch Code 39 tạo ngay trong app (không gọi dịch vụ ngoài).** Thêm bảng ký tự vào `App.Formulas` (đủ cho các ký tự có trong mã `IN-yy-nnnnn` / `PC-yy-nnnnn`; mỗi ký tự là 9 phần tử vạch/khoảng, `w` = rộng, `n` = hẹp):

```powerfx
tblC39 = Table(
    {Ch: "0", P: "nnnwwnwnn"}, {Ch: "1", P: "wnnwnnnnw"}, {Ch: "2", P: "nnwwnnnnw"}, {Ch: "3", P: "wnwwnnnnn"},
    {Ch: "4", P: "nnnwwnnnw"}, {Ch: "5", P: "wnnwwnnnn"}, {Ch: "6", P: "nnwwwnnnn"}, {Ch: "7", P: "nnnwnnwnw"},
    {Ch: "8", P: "wnnwnnwnn"}, {Ch: "9", P: "nnwwnnwnn"}, {Ch: "C", P: "wnwnnwnnn"}, {Ch: "I", P: "nnwnnwwnn"},
    {Ch: "N", P: "nnnnwnnww"}, {Ch: "P", P: "nnwnwnnwn"}, {Ch: "-", P: "nwnnnnwnw"}, {Ch: "*", P: "nwnnwnwnn"}
);
```

```powerfx
// scrLabel.OnVisible — sau ClearCollect(colLabels, …) ở trên
ClearCollect(
    colLabelBars,
    ForAll(
        colLabels As l,
        With(
            {
                // mỗi ký tự (kể cả * đầu/cuối) = 9 phần tử + 1 khoảng cách; bar = vạch, w = độ rộng (hẹp 2, rộng 5, khoảng cách 2)
                els: ForAll(
                    Sequence((Len(l.Code) + 2) * 10) As n,
                    With(
                        {ch: Mid("*" & l.Code & "*", RoundUp(n.Value / 10, 0), 1), pos: Mod(n.Value - 1, 10) + 1},
                        {
                            bar: Mod(pos, 2) = 1,
                            w:   If(pos = 10, 2, If(Mid(LookUp(tblC39, Ch = ch).P, pos, 1) = "w", 5, 2))
                        }
                    )
                )
            },
            With(
                {
                    placed: ForAll(
                        Sequence(CountRows(els)) As i,
                        {x: Sum(FirstN(els, i.Value - 1), w), w: Index(els, i.Value).w, bar: Index(els, i.Value).bar}
                    )
                },
                {
                    Code: l.Code,
                    Img: "data:image/svg+xml;utf8," & EncodeUrl(
                        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='-20 0 " & (Sum(els, w) + 40) & " 40' preserveAspectRatio='none'>" &
                        "<rect x='-20' width='" & (Sum(els, w) + 40) & "' height='40' fill='white'/>" &
                        Concat(Filter(placed, bar), "<rect x='" & x & "' width='" & w & "' height='40' fill='black'/>") &
                        "</svg>")
                }
            )
        )
    )
);

// Image.Image của ô mã vạch trên nhãn;  Visible = cfgLabelBarcode = "Code39"
LookUp(colLabelBars, Code = ThisItem.Code).Img
```

- Thuật toán mã hoá (bảng ký tự, độ rộng, khoảng cách) đã được **kiểm chứng bằng bộ giải mã ZXing** cho `IN-26-00042`, `PC-26-00017` và toàn bộ ký tự `0-9 A-Z - .`; riêng công thức Power Fx ở trên chưa chạy trong Studio.
- Kích thước: khoảng 417 đơn vị rộng (gồm 2 × 20 vùng trống hai bên); nếu vạch hẹp = 0,2 mm thì ảnh rộng ≈ 41,7 mm, cao 8 mm. Với nhãn 50 × 30 mm đặt QR ở trên, mã vạch nằm dưới. Cần thử đọc bằng đúng máy Zebra và nhãn thật.

- Giai đoạn đầu: `Print()` trên trình duyệt desktop, thiết lập kích thước giấy = kích thước nhãn trong hộp thoại in (máy in nhãn Zebra/Brother/TSC cài driver Windows). Hỏi lại loại máy in và kích thước nhãn để chốt template.
- Trên thiết bị di động `Print()` bị hạn chế → dùng desktop để in; điện thoại chỉ dùng để quét.
- Giai đoạn 2: flow sinh PDF nhãn đúng kích thước, in tự động.

### 4.10 `scrAdmin` — Quản trị (chỉ `fxIsAdmin`)

Tab: **Danh mục hoá chất · Vị trí · Cấu hình · Vai trò · Nhật ký**. CRUD danh mục/vị trí ghi trực tiếp bằng `Patch` (Admin có quyền *Contribute* trên các list này); **không có nút xoá** — chỉ "Ngừng sử dụng" (`IsActive = false`). Form hoá chất có ô **Lượng tồn chuẩn** và **Ngưỡng cảnh báo (%)** (placeholder "mặc định 20%"); `PeakQty` chỉ hiển thị, kèm nút "Đặt lại về tồn hiện tại" cho Admin. Nhật ký là Gallery đọc `LabAudit`, lọc theo thời gian, đối tượng, kết quả.

```powerfx
// Thêm hoá chất vào danh mục
Patch(LabCatalog, Defaults(LabCatalog), {
    Title: Trim(txtCatName.Value), CasNumber: Trim(txtCas.Value),
    ChemType: {Value: ddChemType.Selected.Value}, BaseUnit: {Value: ddBaseUnit.Selected.Value},
    HazardClass: ForAll(cmbHazard.SelectedItems, {Value: Value}),
    ParLevelQty: If(IsBlank(txtPar.Value), Blank(), Value(txtPar.Value)),   // lượng tồn chuẩn (mốc 100%)
    LowStockPct: If(IsBlank(txtPct.Value), Blank(), Value(txtPct.Value)),   // để trống = dùng mặc định cfgLowPct
    IsActive: true
})
```

### 4.11 `scrNoAccess`

Hiện khi `fxRole = "None"`: giải thích ngắn, nêu người liên hệ cấp quyền (email Admin từ `LabSettings`), không hiện dữ liệu nào.

## 5. Trạng thái rỗng, đang tải, lỗi

- **Rỗng:** mọi danh sách có thông điệp và nút hành động (ví dụ "Chưa có chai nào — Nhập hoá chất").
- **Đang tải/đang ghi:** khi `varBusy` bật thì khoá nút và hiện spinner; không bao giờ để nút bấm được hai lần.
- **Lỗi nghiệp vụ:** thông báo tiếng Việt từ `varRes.message`, đặt ngay cạnh vùng thao tác (không chỉ toast).
- **Lỗi kết nối:** giữ nguyên dữ liệu đã nhập, cho thử lại với cùng `requestId`.
- Dùng `Notify` cho phản hồi nhẹ; hộp thoại xác nhận riêng cho thao tác không thể hoàn tác (Dispose, Void).

## 6. Quét mã vạch / QR — tóm tắt

| Tình huống | Cách làm |
|---|---|
| **Máy Zebra cầm tay (USB/Bluetooth)** | Máy hoạt động như bàn phím; màn Quét dùng ô nhập + Timer (mục 4.2). Không có camera, không có hình ảnh; chạy được cả trong trình duyệt. |
| Máy Zebra Android (TC/MC) | DataWedge ở chế độ *Keystroke output* vào ô nhập của app. |
| Điện thoại / tablet (phụ) | Control **Barcode reader** (Android, iOS, Power Apps for Windows). **Không chạy trong trình duyệt.** Cần cấp quyền camera. |
| QR chứa link (DeepLink) | Camera điện thoại thường quét → mở app tại `scrScan` với `Param("code")` (cần nhập `AppLink`, đặt `QRMode = DeepLink`). |
| Tạo ảnh QR | Ảnh lấy từ `cfgQRBase` + dữ liệu. **Mặc định là dịch vụ công cộng chỉ để chạy thử**; trước khi go-live thay bằng PCF tạo QR cục bộ hoặc dịch vụ nội bộ (xem rủi ro R-03 trong [05](05-Bao-mat-va-Kiem-thu.md)). |
| Mã vạch tuyến tính (cho máy 1D) | **Code 39 tạo offline trong app** (mục 4.9), không phụ thuộc dịch vụ ngoài. Bật/tắt bằng `LabelBarcode`. |

## 7. Hiệu năng

- Chỉ dùng hàm delegable trên list lớn (`Filter`, `StartsWith`, `LookUp`, `Sort` theo cột index). Mục tiêu: **0 cảnh báo delegation** trong App checker.
- Tải danh mục nhỏ (`colCatalog`, `colLocations`) một lần bằng `Concurrent`.
- `LabLedger` luôn lọc theo (`ItemType`, `ItemID`) hoặc `Created` — không bao giờ tải toàn bộ.
- Hạn chế vòng `ForAll` + `LookUp` trên list lớn; truy xuất chạy tối đa 3 cấp.
- Bật *Explicit column selection*.

## 8. Component dùng chung

| Component | Thuộc tính | Dùng ở |
|---|---|---|
| `cmpNav` | `Items`, `Selected`, `Collapsed` (input) · `OnNavigate` (event) | mọi màn |
| `cmpStatusBadge` | `Status` (input, enum) | Inventory, Detail, Trace |
| `cmpKpiTile` | `Title`, `Value`, `Tone`, `OnSelect` | Home |
| `cmpCodeInput` | `Placeholder` (input) · `OnCode(code)` (event) · chứa `txtScan` + Timer (+ nút camera *Barcode reader* trên màn hình nhỏ) | Scan, PrepRegister, Usage, Trace |
| `cmpQR` | `Code` (input) | Detail, Label |

## 9. Trợ năng (accessibility)

- Tương phản ≥ 4.5:1; trạng thái luôn có **chữ** (không chỉ màu).
- Mục tiêu bấm ≥ 44 × 44 px trên thiết bị cảm ứng.
- Đặt `AccessibleLabel` cho icon/nút chỉ có hình, `TabIndex` theo thứ tự đọc, focus nhìn thấy được.
- Thông báo lỗi gắn với trường (đọc được bằng trình đọc màn hình), không chỉ toast.

## 10. Cần xác nhận khi dựng trong Studio

1. Control *Barcode reader*: tên thuộc tính (`Barcodes`, `OnScan`), và việc nó không chạy trong trình duyệt (chỉ Android, iOS, Power Apps for Windows).
2. Tên hiển thị của từng flow sau khi thêm vào app (`'LAB-F01 RegisterIncoming'.Run` có thể được đặt tên khác) và tên các output (`success`, `message`, `codes`).
3. `JSON()` với giá trị rỗng: schema `Parse JSON` trong flow cho phép `null` ở các trường tuỳ chọn, hoặc app luôn gửi `""`/`0` (công thức trên đã dùng `Coalesce`).
4. Ô nhập (`txtScan.Value`) cập nhật theo từng ký tự máy quét gõ vào để Timer đọc được; Timer đặt trong component có chạy đúng không (nếu không, đặt Timer ở từng màn hình).
5. `AddColumns`/`As` trong `ForAll` với collection chứa cột Choice của SharePoint.
6. `Print()` trên trình duyệt đích và máy in nhãn thực tế.
7. Công thức Code 39 (`Sequence`, `Index`, `Concat`) chạy đúng trong Studio và `Image` hiển thị SVG dạng `data:`; thử quét nhãn in thật bằng máy Zebra.
8. `colStock` dựng từ `colCatalog` với `Filter(colActive, …)` lồng trong `ForAll` cho kết quả đúng với dữ liệu thật.

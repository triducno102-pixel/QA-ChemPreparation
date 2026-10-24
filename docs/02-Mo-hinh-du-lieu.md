# 02 — Mô hình dữ liệu (SharePoint Lists)

> Tài liệu này được **sinh tự động** từ [sharepoint/LabChem.Schema.ps1](../sharepoint/LabChem.Schema.ps1) — đó là nguồn sự thật duy nhất. Muốn đổi cột: sửa file schema, chạy lại script tạo list, chạy `./tools/Build-DataModelDoc.ps1` để sinh lại tài liệu. Đừng sửa tay các bảng bên dưới.

## 1. Nguyên tắc thiết kế

1. **Sổ cái là nguồn sự thật cho lượng còn lại.** Mọi biến động ghi thành một dòng `LabLedger` (chỉ thêm, không sửa/xoá). `RemainingQty` trên `LabLots`/`LabPreps` chỉ là bản cache để hiển thị nhanh, được flow tính lại từ sổ cái. Nhờ vậy có thể kiểm toán và tự sửa lỗi lệch số.
2. **App chỉ đọc, flow mới ghi.** Người dùng chỉ có quyền *Read* trên các list nghiệp vụ; mọi thao tác thay đổi tồn kho đi qua Power Automate (tài khoản dịch vụ) có kiểm tra phía server. Xem [05](05-Bao-mat-va-Kiem-thu.md).
3. **Không xoá.** Sai thì điều chỉnh/đảo bút toán có lý do; list không cấp quyền Delete cho ai ngoài Owner.
4. **Quan hệ bằng `ID` (Number) + mã snapshot (Text), không dùng Lookup column.** Tránh giới hạn 12 cột lookup/view của SharePoint và việc lọc theo lookup không delegable trong Power Apps. Đổi lại, tính toàn vẹn tham chiếu do flow bảo đảm (chỉ flow ghi nên đủ an toàn).
5. **Snapshot tên/hãng/số lô** vào bản ghi con để hồ sơ truy xuất không đổi khi danh mục bị chỉnh sửa về sau (yêu cầu của truy xuất nguồn gốc).
6. **Enum máy dùng khoá tiếng Anh** (`Status`, `TxnType`...), app ánh xạ sang nhãn tiếng Việt và màu — logic không phụ thuộc chuỗi có dấu.
7. **Mỗi chai/đơn vị vật lý = một dòng `LabLots` = một mã QR.** Đăng ký 10 chai cùng lô tạo 10 dòng.
8. **Mọi số lượng lưu theo đơn vị gốc** của hoá chất (g, mL hoặc pcs); đổi đơn vị (mg, kg, µL, L) làm ở giao diện nhập.

## 2. Sơ đồ quan hệ

```mermaid
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
```

**Chuỗi truy xuất:** Biên bản thử nghiệm ← `LabTestUsage` ← dung dịch pha (`LabPreps`) ← `LabPrepItems` ← chai đầu vào (`LabLots`, kèm số lô NSX + COA) — và đệ quy nếu thành phần lại là một dung dịch pha khác (dung dịch gốc → dung dịch làm việc).

## 3. Định danh và nội dung QR

| Đối tượng | Mã | Cách sinh |
|---|---|---|
| Chai đầu vào | `IN-yy-nnnnn` (vd `IN-26-00042`) | `yy` = 2 số cuối năm, `nnnnn` = SharePoint `ID` của item, đệm 5 chữ số |
| Dung dịch pha | `PC-yy-nnnnn` (vd `PC-26-00017`) | tương tự, theo `ID` của `LabPreps` |

- Flow tạo item với `Title` tạm (GUID) rồi cập nhật `Title` = mã tính từ `ID` → **không có race condition** khi nhiều người đăng ký cùng lúc, không cần bảng bộ đếm.
- `Title` đặt *Enforce unique values* nên không thể trùng mã.
- Mã không tái sử dụng, kể cả khi item bị vô hiệu.
- **Nội dung QR** (cấu hình `QRMode`): `CodeOnly` = chỉ chứa mã (ưu tiên: mọi đầu đọc đều hiểu, không lộ thông tin); `DeepLink` = `<AppLink>&code=<mã>` để quét bằng camera điện thoại là mở thẳng app. Parser trong app hiểu cả hai dạng.

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

Flow luôn kiểm tra `Unit` của giao dịch khớp `Unit` của đối tượng; không bao giờ tự quy đổi phía server (tránh sai âm thầm).

## 5. Quy tắc nghiệp vụ (flow thực thi phía server)

| Mã | Quy tắc |
|---|---|
| BR-01 | `RemainingQty` = Σ `QtyDelta` của `LabLedger` theo (`ItemType`, `ItemID`). |
| BR-02 | Số dư không được âm: giao dịch làm số dư < 0 bị từ chối và ghi `LabAudit` (Result = Rejected). |
| BR-03 | Chỉ được dùng (pha / thử nghiệm) đối tượng có `Status` ∈ {Available, InUse}, `ExpiryDate` ≥ ngày giao dịch, `IsVoid` = false; dung dịch pha còn phải có `ReviewStatus` ≠ Rejected. Quarantine / Empty / Expired / Disposed bị chặn. |
| BR-04 | `Unit` của giao dịch phải bằng `Unit` của đối tượng. |
| BR-05 | Nếu `EnforcePrepExpiryLimit` = true: `ExpiryDate` dung dịch pha ≤ hạn dùng sớm nhất của các thành phần. |
| BR-06 | Không xoá. Sai sót sửa bằng `Adjust` / `Reversal` kèm lý do (Admin). `Void` chỉ khi đối tượng chưa phát sinh hậu duệ (chưa dùng để pha, chưa gắn biên bản); nếu đã có thì phải `Dispose`. |
| BR-07 | Mỗi chai một mã; mã không tái sử dụng. |
| BR-08 | Người duyệt (`ReviewedBy`) phải khác người pha (`PreparedBy`). |
| BR-09 | Dùng cho thử nghiệm thì bắt buộc có `Số biên bản`. |
| BR-10 | `Status` tự động: số dư = 0 → Empty; 0 < số dư < ban đầu → InUse; quá hạn → Expired (job hằng ngày). Chai/dung dịch Expired hoặc Empty vẫn tra cứu và truy xuất được. |
| BR-11 | Công thức pha (`LabPrepItems`) bất biến sau khi tạo. |
| BR-12 | Mỗi yêu cầu ghi mang `RequestId` (GUID); gửi lại cùng `RequestId` trả kết quả cũ, không ghi trùng. |
| BR-13 | **Cảnh báo sắp hết (cần mua thêm):** với mỗi hoá chất, `Tổng tồn` = Σ `RemainingQty` của các chai `Available`/`InUse`/`Quarantine` (hàng đã nhập nhưng đang chờ kiểm vẫn tính là có hàng, để không mua trùng). `Mốc 100%` = `ParLevelQty` nếu có, ngược lại `PeakQty`. `Ngưỡng` = `LowStockPct` của hoá chất nếu có, ngược lại `DefaultLowStockPct`. Cảnh báo khi `Tổng tồn < Mốc 100% × Ngưỡng / 100` (kể cả khi đã hết sạch). Riêng từng chai đang dùng: tô vàng khi `RemainingQty / InitialQty × 100 < Ngưỡng`. |

## 6. Cấu hình mặc định (`LabSettings`)

| Khoá | Giá trị | Ý nghĩa |
|---|---|---|
| `LabName` | `Phòng thí nghiệm` | Tên hiển thị trên tiêu đề app và nhãn. |
| `ExpiryWarnDays` | `30` | Cảnh báo hoá chất/dung dịch sắp hết hạn trong N ngày. |
| `DefaultLowStockPct` | `20` | Ngưỡng cảnh báo sắp hết (%) mặc định, dùng cho hoá chất không tự đặt LowStockPct. Chai đang dùng dưới % này (so với lượng ban đầu) cũng được tô vàng. |
| `LabelBarcode` | `Code39` | Mã vạch tuyến tính in thêm trên nhãn để máy quét 1D (laser) đọc được: Code39 hoặc None. QR luôn được in. |
| `RequireIncomingRelease` | `false` | true: hoá chất mới nhập ở trạng thái Quarantine, Reviewer/Admin phải Release mới dùng được. |
| `EnforcePrepExpiryLimit` | `true` | true: hạn dùng dung dịch pha không được vượt hạn dùng sớm nhất của thành phần. |
| `MaxBottlesPerReceipt` | `20` | Số chai tối đa tạo trong một lần đăng ký nhập. |
| `AlertEmails` | _(trống)_ | Danh sách email nhận báo cáo hằng ngày (phân tách bằng dấu chấm phẩy). |
| `ReportUrlAllowedHosts` | _(trống)_ | Hậu tố host được phép cho link biên bản/COA, phân tách bằng dấu chấm phẩy (vd .sharepoint.com). Trống = mọi https. |
| `QRMode` | `CodeOnly` | CodeOnly: QR chứa mã nội bộ. DeepLink: QR chứa link mở thẳng app (cần AppLink). |
| `QRBaseUrl` | `https://api.qrserver.com/v1/create-qr-code/?size=300x300&margin=0&data=` | PILOT ONLY. Dịch vụ tạo ảnh QR công cộng, chỉ nhận mã nội bộ. Thay bằng PCF/dịch vụ nội bộ trước khi go-live (xem docs/05). |
| `AppLink` | _(trống)_ | Link play của app, ví dụ https://apps.powerapps.com/play/<appId>?tenantId=<tid>. Dùng khi QRMode=DeepLink. |

## 7. Dung lượng và giới hạn SharePoint

- Ước tính tham khảo: 3.000 chai + 2.000 dung dịch/năm → `LabLedger` ~ 40.000 dòng/năm. SharePoint chứa tới 30 triệu item/list; ngưỡng 5.000 chỉ chặn truy vấn **không có index** → các cột lọc/sắp xếp đều đã đánh index.
- App đặt *Data row limit* = 2.000 và chỉ dùng hàm delegable (`Filter`, `StartsWith`, `LookUp`, `Sort` theo cột index). KPI dạng đếm (`CountRows`) chính xác đến 2.000 kết quả/phép lọc; nếu số chai đang quản lý vượt ngưỡng này thì chuyển KPI sang snapshot do flow hằng ngày ghi vào `LabSettings`.
- Mỗi list tối đa 20 cột index (hiện dùng ≤ 8).
- Lưu trữ dài hạn: theo quy định hồ sơ của phòng lab (ví dụ ISO/IEC 17025 thường yêu cầu giữ hồ sơ nhiều năm) — chưa xác nhận với anh, xem câu hỏi mở trong [01](01-Thiet-ke-tong-the.md).

---

## Phụ lục — Chi tiết từng list

### 1. LabCatalog — Danh mục hoá chất

Danh mục hoá chất (master data). Chỉ Admin chỉnh sửa.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Tên hoá chất | Văn bản | ✔ | ✔ |  | |
| `CasNumber` | Số CAS | Văn bản |  | ✔ |  |  |
| `ChemType` | Loại | Lựa chọn |  |  | Chất gốc, Dung môi, Chất chuẩn, Dung dịch đệm, Môi trường, Khác (mặc định: Chất gốc) |  |
| `Grade` | Cấp độ tinh khiết | Lựa chọn |  |  | AR, GR, ACS, HPLC, LC-MS, Technical, CRM, Khác |  |
| `BaseUnit` | Đơn vị gốc | Lựa chọn | ✔ |  | g, mL, pcs (mặc định: g) | Mọi số lượng của hoá chất này đều lưu theo đơn vị gốc (g, mL hoặc pcs). |
| `HazardClass` | Phân loại nguy hiểm (GHS) | Nhiều lựa chọn |  |  | Dễ cháy, Ăn mòn, Độc cấp tính, Oxy hoá, Kích ứng, Nguy hại sức khoẻ, Nguy hại môi trường, Khí nén, Dễ nổ, Không nguy hiểm |  |
| `StorageCondition` | Điều kiện bảo quản | Lựa chọn |  |  | 15-25 °C (phòng), 2-8 °C, -20 °C, -80 °C, Tủ chống cháy, Tủ hút, Tránh ánh sáng |  |
| `ParLevelQty` | Lượng tồn chuẩn | Số |  |  | 4 số lẻ, ≥ 0 | Lượng muốn có khi kho đầy đủ (đơn vị gốc). Là mốc 100% để tính % còn lại. Để trống = hệ thống dùng PeakQty. |
| `LowStockPct` | Ngưỡng cảnh báo (%) | Số |  |  | 0 số lẻ, ≥ 1, ≤ 99 | Cảnh báo cần mua thêm khi tổng tồn nhỏ hơn % này của lượng tồn chuẩn. Để trống = dùng DefaultLowStockPct trong LabSettings. |
| `PeakQty` | Tồn cao nhất đã đạt | Số |  |  | 4 số lẻ, ≥ 0 | Hệ thống tự cập nhật (LAB-F01) sau mỗi lần nhập = tổng tồn lớn nhất từng đạt. Dùng làm lượng chuẩn khi ParLevelQty trống; Admin có thể đặt lại. |
| `SDSLink` | Link SDS | Hyperlink |  |  |  |  |
| `IsActive` | Đang sử dụng | Có/Không |  |  | mặc định: Có |  |

### 2. LabLocations — Vị trí lưu trữ

Vị trí lưu trữ (phòng / tủ / ngăn).

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Tên vị trí | Văn bản | ✔ | ✔ | duy nhất | |
| `Room` | Phòng | Văn bản |  |  |  |  |
| `Note` | Ghi chú | Nhiều dòng |  |  |  |  |
| `IsActive` | Đang sử dụng | Có/Không |  |  | mặc định: Có |  |

### 3. LabLots — Hoá chất đầu vào (mỗi chai một dòng)

Hoá chất đầu vào. Mỗi item = 1 chai/đơn vị vật lý, có 1 mã QR riêng. Chỉ flow được ghi.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Mã nội bộ | Văn bản | ✔ | ✔ | duy nhất | |
| `CatalogID` | ID danh mục | Số | ✔ | ✔ | 0 số lẻ | ID item trong LabCatalog. |
| `ChemName` | Tên hoá chất | Văn bản | ✔ | ✔ |  | Snapshot tại thời điểm nhập, để tra cứu nhanh không cần join. |
| `CasNumber` | Số CAS | Văn bản |  |  |  | Snapshot. |
| `MfgLot` | Số lô NSX | Văn bản |  | ✔ |  |  |
| `Manufacturer` | Hãng sản xuất | Văn bản |  |  |  |  |
| `Supplier` | Nhà cung cấp | Văn bản |  |  |  |  |
| `ReceivedDate` | Ngày nhận | Ngày | ✔ | ✔ |  |  |
| `MfgDate` | Ngày sản xuất | Ngày |  |  |  |  |
| `ExpiryDate` | Hạn dùng | Ngày |  | ✔ |  |  |
| `OpenedDate` | Ngày mở nắp | Ngày |  |  |  | Flow gán khi giao dịch xuất đầu tiên phát sinh (nếu để trống). |
| `InitialQty` | Lượng ban đầu | Số | ✔ |  | 4 số lẻ, ≥ 0 |  |
| `RemainingQty` | Lượng còn lại | Số |  |  | 4 số lẻ, ≥ 0 | Cache. Luôn bằng tổng QtyDelta của LabLedger; chỉ flow LAB-C01 cập nhật. |
| `Unit` | Đơn vị | Lựa chọn | ✔ |  | g, mL, pcs |  |
| `LocationID` | ID vị trí | Số |  |  | 0 số lẻ |  |
| `LocationName` | Vị trí | Văn bản |  |  |  | Snapshot tên vị trí. |
| `Status` | Trạng thái | Lựa chọn | ✔ | ✔ | Quarantine, Available, InUse, Empty, Expired, Disposed (mặc định: Available) |  |
| `COALink` | Link COA | Hyperlink |  |  |  |  |
| `RegisteredBy` | Người đăng ký | Người |  |  |  | Người gọi flow (lấy từ danh tính, không nhận từ client). |
| `Note` | Ghi chú | Nhiều dòng |  |  |  |  |
| `IsVoid` | Đã vô hiệu | Có/Không |  |  | mặc định: Không |  |
| `VoidReason` | Lý do vô hiệu | Nhiều dòng |  |  |  |  |

### 4. LabPreps — Hoá chất pha

Hoá chất pha chế / dung dịch pha. Chỉ flow được ghi.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Mã hoá chất pha | Văn bản | ✔ | ✔ | duy nhất | |
| `PrepName` | Tên dung dịch | Văn bản | ✔ | ✔ |  |  |
| `PrepType` | Loại dung dịch | Lựa chọn |  |  | Dung dịch gốc, Dung dịch làm việc, Dung dịch đệm, Thuốc thử, Pha loãng, Khác (mặc định: Dung dịch làm việc) |  |
| `Concentration` | Nồng độ | Văn bản |  |  |  | Văn bản tự do, ví dụ "0.1 mol/L", "1000 ppm". |
| `SOPRef` | SOP / phương pháp | Văn bản |  |  |  |  |
| `Procedure` | Cách pha | Nhiều dòng |  |  |  |  |
| `PrepDate` | Ngày pha | Ngày | ✔ | ✔ |  |  |
| `ExpiryDate` | Hạn dùng | Ngày | ✔ | ✔ |  | Không vượt hạn dùng sớm nhất của thành phần (cấu hình EnforcePrepExpiryLimit). |
| `FinalQty` | Lượng sau pha | Số | ✔ |  | 4 số lẻ, ≥ 0 |  |
| `RemainingQty` | Lượng còn lại | Số |  |  | 4 số lẻ, ≥ 0 | Cache. Luôn bằng tổng QtyDelta của LabLedger. |
| `Unit` | Đơn vị | Lựa chọn | ✔ |  | g, mL, pcs |  |
| `LocationID` | ID vị trí | Số |  |  | 0 số lẻ |  |
| `LocationName` | Vị trí | Văn bản |  |  |  |  |
| `StorageCondition` | Điều kiện bảo quản | Lựa chọn |  |  | 15-25 °C (phòng), 2-8 °C, -20 °C, -80 °C, Tủ chống cháy, Tủ hút, Tránh ánh sáng |  |
| `Status` | Trạng thái | Lựa chọn | ✔ | ✔ | Available, InUse, Empty, Expired, Disposed (mặc định: Available) |  |
| `ReviewStatus` | Trạng thái duyệt | Lựa chọn |  |  | Pending, Approved, Rejected (mặc định: Pending) |  |
| `ReviewedBy` | Người duyệt | Người |  |  |  | Phải khác PreparedBy (nguyên tắc 4 mắt). |
| `ReviewedOn` | Ngày duyệt | Ngày giờ |  |  |  |  |
| `PreparedBy` | Người pha | Người |  |  |  |  |
| `Note` | Ghi chú | Nhiều dòng |  |  |  |  |
| `IsVoid` | Đã vô hiệu | Có/Không |  |  | mặc định: Không |  |
| `VoidReason` | Lý do vô hiệu | Nhiều dòng |  |  |  |  |

### 5. LabPrepItems — Thành phần của mỗi lần pha

Thành phần của mỗi lần pha (công thức thực tế). Nguồn có thể là chai đầu vào hoặc một dung dịch pha khác.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Mã hoá chất pha | Văn bản | ✔ | ✔ |  | |
| `PrepID` | ID dung dịch pha | Số | ✔ | ✔ | 0 số lẻ |  |
| `SourceType` | Loại nguồn | Lựa chọn | ✔ |  | Lot, Prep |  |
| `SourceID` | ID nguồn | Số | ✔ | ✔ | 0 số lẻ |  |
| `SourceCode` | Mã nguồn | Văn bản | ✔ | ✔ |  |  |
| `SourceName` | Tên nguồn | Văn bản |  |  |  | Snapshot. |
| `SourceMfgLot` | Số lô NSX nguồn | Văn bản |  |  |  | Snapshot, chỉ có khi nguồn là Lot; phục vụ truy xuất nhanh. |
| `ItemRole` | Vai trò | Lựa chọn |  |  | Chất tan, Dung môi, Phụ gia (mặc định: Chất tan) |  |
| `QtyUsed` | Lượng dùng | Số | ✔ |  | 4 số lẻ, ≥ 0 |  |
| `Unit` | Đơn vị | Lựa chọn | ✔ |  | g, mL, pcs |  |

### 6. LabLedger — Sổ cái xuất/nhập

Sổ cái xuất/nhập (append-only). Số dư của Lot/Prep = tổng QtyDelta. Nguồn sự thật cho lượng còn lại.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Mã đối tượng | Văn bản | ✔ | ✔ |  | |
| `ItemType` | Loại đối tượng | Lựa chọn | ✔ |  | Lot, Prep |  |
| `ItemID` | ID đối tượng | Số | ✔ | ✔ | 0 số lẻ |  |
| `TxnType` | Loại giao dịch | Lựa chọn | ✔ |  | Receive, PrepCreate, PrepUse, TestUse, Adjust, Dispose, Reversal |  |
| `QtyDelta` | Biến động | Số | ✔ |  | 4 số lẻ | Dương = nhập, âm = xuất. |
| `Unit` | Đơn vị | Lựa chọn | ✔ |  | g, mL, pcs |  |
| `BalanceAfter` | Số dư sau GD | Số |  |  | 4 số lẻ |  |
| `RefType` | Loại tham chiếu | Lựa chọn |  |  | Prep, Report, Manual |  |
| `RefCode` | Mã tham chiếu | Văn bản |  | ✔ |  | Mã dung dịch pha hoặc số biên bản liên quan. |
| `Reason` | Lý do | Nhiều dòng |  |  |  | Bắt buộc với Adjust / Dispose / Reversal. |
| `Actor` | Người thực hiện | Người |  |  |  |  |

### 7. LabTestUsage — Liên kết biên bản thử nghiệm

Liên kết biên bản thử nghiệm với hoá chất đã dùng (1 dòng = 1 biên bản x 1 hoá chất).

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Số biên bản | Văn bản | ✔ | ✔ |  | |
| `ReportUrl` | Link biên bản | Hyperlink |  |  |  |  |
| `TestName` | Phép thử / chỉ tiêu | Văn bản |  |  |  |  |
| `SampleCode` | Mã mẫu | Văn bản |  |  |  |  |
| `ItemType` | Loại đối tượng | Lựa chọn | ✔ |  | Lot, Prep |  |
| `ItemID` | ID đối tượng | Số | ✔ | ✔ | 0 số lẻ |  |
| `ItemCode` | Mã hoá chất | Văn bản | ✔ | ✔ |  |  |
| `ItemName` | Tên hoá chất | Văn bản |  |  |  | Snapshot. |
| `QtyUsed` | Lượng dùng | Số | ✔ |  | 4 số lẻ, ≥ 0 |  |
| `Unit` | Đơn vị | Lựa chọn | ✔ |  | g, mL, pcs |  |
| `UsedDate` | Ngày sử dụng | Ngày giờ | ✔ | ✔ |  |  |
| `Analyst` | Người thử nghiệm | Người |  |  |  |  |
| `Note` | Ghi chú | Nhiều dòng |  |  |  |  |

### 8. LabAudit — Nhật ký kiểm toán

Nhật ký kiểm toán nghiệp vụ (append-only). Lưu thành công lẫn bị từ chối. Admin/Reviewer đọc.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Hành động | Văn bản | ✔ | ✔ |  | |
| `EntityType` | Loại đối tượng | Lựa chọn | ✔ |  | Lot, Prep, Catalog, Report, System |  |
| `EntityCode` | Mã đối tượng | Văn bản |  | ✔ |  |  |
| `Result` | Kết quả | Lựa chọn | ✔ |  | Success, Rejected, Error |  |
| `Detail` | Chi tiết | Nhiều dòng |  |  |  | JSON kết quả / lý do từ chối. Dùng để trả lại kết quả khi client gửi lại cùng RequestId. |
| `Actor` | Người thực hiện | Người |  |  |  |  |
| `RequestId` | Request Id | Văn bản |  | ✔ |  | GUID do app sinh; chống ghi trùng khi bấm 2 lần / flow retry. |
| `RunId` | Flow run Id | Văn bản |  |  |  |  |

### 9. LabRoles — Phân quyền nghiệp vụ

Phân quyền nghiệp vụ. Flow kiểm tra vai trò ở phía server; app chỉ dùng để ẩn/hiện chức năng.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Email (UPN, chữ thường) | Văn bản | ✔ | ✔ | duy nhất | |
| `DisplayName` | Họ tên | Văn bản |  |  |  |  |
| `Role` | Vai trò | Lựa chọn | ✔ |  | Admin, Analyst, Reviewer, Viewer (mặc định: Viewer) |  |
| `IsActive` | Đang hiệu lực | Có/Không |  |  | mặc định: Có |  |

### 10. LabSettings — Cấu hình

Cấu hình dạng khoá-giá trị. Chỉ Admin chỉnh sửa.

| Cột (InternalName) | Hiển thị | Kiểu | Bắt buộc | Index | Giá trị / mặc định | Ghi chú |
|---|---|---|:-:|:-:|---|---|
| `Title` | Khoá | Văn bản | ✔ | ✔ | duy nhất | |
| `Value` | Giá trị | Văn bản |  |  |  |  |
| `Description` | Mô tả | Nhiều dòng |  |  |  |  |


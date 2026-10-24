# 05 — Bảo mật, rủi ro và kế hoạch kiểm thử

## 1. Mô hình tin cậy

```
Người dùng ──(danh tính M365)──► Power Apps ──(đọc, quyền của chính họ)──► SharePoint Lists  (Read-only)
                                      │
                                      └─(payload JSON)─► Power Automate ──(tài khoản dịch vụ)──► SharePoint Lists (ghi)
                                                          ▲ kiểm tra: danh tính người gọi, vai trò, nghiệp vụ, RequestId
```

Ba nguyên tắc:

1. **Không tin client.** App chỉ là giao diện; ẩn nút theo vai trò chỉ để dễ dùng. Mọi kiểm tra quyền và nghiệp vụ lặp lại ở flow.
2. **Người dùng không có quyền ghi trực tiếp** vào list nghiệp vụ; muốn thay đổi phải đi qua flow có kiểm tra và ghi nhật ký.
3. **Không xoá, chỉ thêm.** Sai thì đảo bút toán có lý do; sổ cái và nhật ký chỉ cho thêm.

## 2. Phân quyền

### 2.1 Vai trò nghiệp vụ (lưu ở `LabRoles`, flow kiểm tra phía server)

| Chức năng | Admin | Analyst | Reviewer | Viewer |
|---|:-:|:-:|:-:|:-:|
| Quét, tra cứu, xem tồn, truy xuất | ✔ | ✔ | ✔ | ✔ |
| Đăng ký hoá chất đầu vào (F01) | ✔ | ✔ | | |
| Đăng ký pha chế (F02) | ✔ | ✔ | | |
| Ghi nhận sử dụng / gắn biên bản (F03) | ✔ | ✔ | | |
| Duyệt dung dịch pha, Release hoá chất kiểm nhập (F04) | ✔ | | ✔ | |
| Điều chỉnh, Huỷ bỏ, Vô hiệu (F04) | ✔ | | | |
| Quản lý danh mục, vị trí, cấu hình, vai trò | ✔ | | | |
| Xem nhật ký kiểm toán | ✔ | | ✔ | |

Quy tắc tách nhiệm: người duyệt dung dịch ≠ người pha (BR-08). Nên có ít nhất hai Admin để Admin này duyệt việc của Admin kia.

### 2.2 Quyền SharePoint (áp bởi `New-LabChemLists.ps1 -ApplyPermissions`)

| List | Owner | Tài khoản dịch vụ | Admins | Analysts / Viewers | Reviewers |
|---|---|---|---|---|---|
| `LabCatalog`, `LabLocations`, `LabSettings`, `LabRoles` | Full | Ghi (không xoá) | Contribute | Read | Read |
| `LabLots`, `LabPreps`, `LabLedger` | Full | Ghi (không xoá) | Read | Read | Read |
| `LabPrepItems`, `LabTestUsage` | Full | **Chỉ thêm** | Read | Read | Read |
| `LabAudit` | Full | **Chỉ thêm** | Read | **Không** | Read |

- Hai permission level tuỳ biến: *LabChem Writer (No Delete)* và *LabChem Append Only*.
- Ngoài nhóm Owner, **không ai có quyền xoá** item. Người dùng thường không thể sửa số lượng bằng giao diện SharePoint.
- `LabRoles` (đọc được bởi mọi người dùng lab) cho biết ai giữ vai trò gì — chấp nhận ở quy mô lab; nếu không muốn, chuyển việc tra vai trò sang flow.

## 3. Kiểm soát theo mối đe doạ

| ID | Mối đe doạ | Kiểm soát | Kiểm thử |
|---|---|---|---|
| S-1 | Giả mạo danh tính người thao tác | Flow lấy người gọi từ header `x-ms-user-email-encoded` (hoặc `My profile` với connection của người chạy), **không** nhận email từ client; `Actor`, `RegisteredBy`, `PreparedBy` ghi từ danh tính này | T-SEC-01 |
| S-2 | Người không có vai trò gọi thẳng flow qua API | Mỗi flow kiểm `LabRoles` ở bước 0.6; từ chối + ghi `LabAudit` | T-SEC-02, 06 |
| T-1 | Sửa tay `RemainingQty`, sổ cái, công thức pha | Quyền Read cho người dùng; versioning 500 phiên bản; `LAB-S02` đối soát hằng đêm và sửa theo sổ cái; ledger/prep-items/test-usage chỉ cho thêm | T-SEC-03, T-RM-03 |
| T-2 | Chèn dữ liệu độc hại qua payload (OData injection, công thức Excel, HTML) | Flow xác thực kiểu/độ dài mọi trường; chuỗi do người dùng **không bao giờ** nối vào `$filter` — lọc bằng `ID` số, `RequestId` phải đúng 36 ký tự GUID, mọi chuỗi còn lại phải escape `'` → `''`; dữ liệu hiển thị qua control Power Apps (không render HTML); nếu sau này xuất CSV/Excel thì thêm tiền tố `'` cho ô bắt đầu bằng `= + - @` | T-SEC-07 |
| R-1 | Chối bỏ thao tác | `LabAudit` (thành công/bị từ chối/lỗi) + sổ cái + version history; không dựa vào run history của flow vì chỉ lưu ~28 ngày | T-SEC-11 |
| I-1 | Lộ dữ liệu cho người ngoài | Chia sẻ app cho **nhóm bảo mật** lab; tắt chia sẻ ngoài tổ chức và link "Anyone" trên site; không dùng nhóm "Everyone" | T-SEC-09 |
| I-2 | Lộ mã/URL qua dịch vụ tạo QR công cộng | Giai đoạn thử: chỉ gửi **mã nội bộ** (`IN-26-00042`) — không có tên hoá chất, tenant hay app ID; trước go-live thay bằng PCF tạo QR cục bộ hoặc dịch vụ nội bộ (rủi ro R-03) | T-SEC-12 |
| I-3 | Link biên bản/COA độc hại | Flow chỉ nhận `https://`, có thể giới hạn theo host (`ReportUrlAllowedHosts`); app kiểm tra lại trước `Launch()` | T-SEC-08 |
| D-1 | Quá tải: bấm liên tục, nhập hàng loạt | Khoá nút khi `varBusy`; `MaxBottlesPerReceipt`; idempotency theo `RequestId` | T-IN-07 |
| E-1 | Nâng quyền: Analyst tự điều chỉnh tồn | Điều chỉnh/huỷ chỉ Admin, kiểm ở flow; thao tác bắt buộc có lý do; lưu cả lúc bị từ chối | T-SEC-06 |
| E-2 | Chiếm tài khoản dịch vụ (ghi mọi thứ) | Không cấp giấy phép/hộp thư thừa, chặn đăng nhập tương tác, Conditional Access, giám sát sign-in; quyền tối thiểu (không xoá); 2 co-owner là Admin lab | Rà soát cấu hình |

## 4. Danh sách kiểm tra trước go-live

**Tenant / môi trường**
- [ ] Môi trường Dev → Test → Prod, đóng gói bằng Solution; flow và connection thuộc tài khoản dịch vụ, có 2 co-owner.
- [ ] Chính sách DLP: nhóm *Business* gồm SharePoint, Outlook, Approvals, Teams; không cho trộn với connector ngoài.
- [ ] Site SharePoint riêng cho LabChem; tắt chia sẻ ngoài; xoá "Everyone except external users"; chỉ nhóm `LabChem *` và Owner có quyền.
- [ ] Đã chạy script với `-ApplyPermissions` và kiểm tra lại bằng tài khoản Analyst/Viewer thật.
- [ ] Bật Purview audit; đặt retention (không cho xoá) cho các list nghiệp vụ theo quy định hồ sơ của phòng lab.
- [ ] Cảnh báo lỗi flow gửi tới nhóm Admin (không chỉ người tạo).

**Ứng dụng**
- [ ] Thay `QRBaseUrl` bằng nguồn QR nội bộ/PCF; kiểm tra không còn lệnh gọi ra dịch vụ công cộng (Network trong Monitor).
- [ ] App checker: 0 cảnh báo delegation, 0 lỗi accessibility.
- [ ] Ít nhất 2 người có vai trò Admin; vai trò mặc định cho người lạ là `None`.

**Vận hành**
- [ ] Runbook: cấp/thu hồi vai trò (cập nhật cả `LabRoles` **và** nhóm SharePoint), xử lý cảnh báo đối soát, quy trình điều chỉnh tồn.
- [ ] Sao lưu: xuất `LabLedger` và `LabAudit` định kỳ (hằng tháng) ra kho lưu trữ; thử khôi phục từ thùng rác/versions.
- [ ] Theo dõi: email tổng hợp hằng ngày từ `LAB-S01`, cảnh báo lệch từ `LAB-S02`.

## 5. Rủi ro và hạn chế đã biết

| ID | Rủi ro / hạn chế | Mức | Cách xử lý hiện tại | Khi nào xử lý triệt để |
|---|---|---|---|---|
| R-01 | Instant flow không có concurrency control → hai người trừ cùng một chai trong vài giây có thể đua | Thấp | Kiểm tra lại sau khi ghi trong `LAB-C01`, bù `Reversal` nếu âm; `LAB-S02` đối soát | Nếu phòng lab đông người dùng đồng thời: chuyển sang Dataverse hoặc cơ chế khoá |
| R-02 | Nhập nhiều chai/nhiều thành phần gần ngưỡng chờ 2 phút của Power Apps | Thấp | Chạy song song 5 luồng, giới hạn 20 chai và 30 thành phần | Chuyển sang xử lý bất đồng bộ + thông báo khi xong |
| R-03 | QR sinh bởi dịch vụ công cộng (chỉ để thử) | **Trung bình** | Chỉ gửi mã nội bộ; cấu hình thay được | **Trước go-live** |
| R-04 | Vai trò duy trì ở hai nơi (`LabRoles` và nhóm SharePoint) dễ lệch | Trung bình | Runbook + kiểm tra định kỳ | Giai đoạn 2: flow đồng bộ |
| R-05 | Child flow/Solution cần environment có Dataverse và giấy phép phù hợp | Trung bình | Phương án thay: sao chép Scope vào từng flow | Xác nhận với IT trước khi bắt đầu |
| R-06 | Ngưỡng 5.000 item/delegation khi dữ liệu lớn | Thấp (hiện tại) | Index, hàm delegable, KPI giới hạn 2.000 | Snapshot KPI bằng flow; lưu trữ ledger cũ |
| R-07 | Biên bản thử nghiệm nằm ngoài hệ thống: đổi tên/di chuyển file làm hỏng liên kết | Trung bình | Lưu `Số biên bản` làm khoá chính, link chỉ là tiện ích | Quy ước thư viện biên bản cố định; ID bền (nếu có) |
| R-08 | Header danh tính người gọi có thể không có ở mọi tenant | Trung bình | Phương án thay bằng `My profile (V2)` | Xác nhận ở T-SEC-01 |
| R-09 | Owner của site vẫn sửa được dữ liệu | Thấp | Giới hạn số Owner; versioning; đối soát; Purview audit | — |
| R-10 | `Print()` hạn chế trên di động / chưa biết loại máy in nhãn | Thấp | In từ máy tính; chốt máy in và kích thước nhãn | Giai đoạn 2: flow sinh PDF nhãn |
| R-11 | Máy quét Zebra 1D (laser, ví dụ LS2208) không đọc được QR | Trung bình | Nhãn in thêm mã vạch Code 39 (tạo offline trong app, đã kiểm chứng thuật toán bằng bộ giải mã); cần thử bằng đúng máy | Chốt model máy quét ở giai đoạn 0 |
| R-12 | Control quét camera *Barcode reader* không chạy trong trình duyệt; ô nhập nhận dữ liệu từ máy quét phải giữ focus | Thấp | Máy cầm tay là cách chính (ô nhập + Timer); camera chỉ hiện trên điện thoại/tablet | Kiểm thử T-SC-02, T-SC-09 trên thiết bị thật |

## 6. Kế hoạch kiểm thử

### 6.1 Chiến lược
- **Môi trường:** Test riêng, sao từ Dev; dữ liệu giả có số lượng nhỏ cho chức năng và bộ dữ liệu lớn cho hiệu năng (5.000 chai, 40.000 dòng sổ cái).
- **Tài khoản thử:** 1 Admin, 2 Analyst, 1 Reviewer, 1 Viewer, 1 người không có vai trò, 1 người ngoài nhóm bảo mật.
- **Lớp kiểm:** (1) chức năng theo từng yêu cầu, (2) bất biến dữ liệu bằng truy vấn đối chiếu, (3) phân quyền/bảo mật, (4) đồng thời, (5) hiệu năng, (6) thiết bị thực (camera, súng quét, máy in), (7) UAT với người dùng thật.
- **Đối chiếu bất biến sau mỗi bài kiểm:** với mọi Lot/Prep, `RemainingQty` = Σ `QtyDelta` và ≥ 0.

### 6.2 Ca kiểm thử

**Đăng ký hoá chất đầu vào (yêu cầu 1)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-IN-01 | Nhập 1 chai hợp lệ | Mã `IN-yy-nnnnn`; `RemainingQty = InitialQty`; 1 dòng `Receive`; audit Success; chuyển sang màn in nhãn |
| T-IN-02 | Nhập 5 chai; hai người nhập đồng thời | 5 mã khác nhau mỗi người, không trùng, mỗi chai có dòng sổ cái |
| T-IN-03 | Hạn dùng ≤ ngày nhận | Từ chối, không tạo bản ghi nào |
| T-IN-04 | Nhập 500 mg cho chất có đơn vị gốc g | Lưu 0,5 g |
| T-IN-05 | Gọi flow trực tiếp với đơn vị khác nhóm (mL cho chất g) | Từ chối + audit; UI không cho chọn |
| T-IN-06 | `bottleCount` = 21 hoặc 0 | Từ chối |
| T-IN-07 | Bấm Lưu hai lần liên tiếp; ngắt mạng rồi thử lại | Chỉ một bộ bản ghi (cùng `RequestId`) |
| T-IN-08 | `coaLink` = `javascript:alert(1)` hoặc `http://` | Từ chối |
| T-IN-09 | `RequireIncomingRelease = true` | Trạng thái Quarantine, không pha/dùng được cho tới khi Release |
| T-IN-10 | Danh mục `IsActive = false` | Từ chối |

**Đăng ký pha chế (yêu cầu 2)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-PR-01 | Pha từ 2 chai hợp lệ | Mã `PC-…`; 2 dòng `LabPrepItems` có snapshot số lô; nguồn bị trừ đúng; `PrepUse` âm + `PrepCreate` dương; `RemainingQty = FinalQty` |
| T-PR-02 | Lượng dùng > còn lại | UI báo tại dòng; gọi flow trực tiếp vẫn bị từ chối; tồn nguồn không đổi |
| T-PR-03 | Thành phần Quarantine / Expired / Empty / Disposed / hết hạn | Chặn ở UI và flow |
| T-PR-04 | Hạn dùng pha > hạn sớm nhất của thành phần (bật `EnforcePrepExpiryLimit`) | Từ chối, nêu rõ thành phần giới hạn |
| T-PR-05 | Pha dung dịch làm việc từ dung dịch gốc (2 cấp) | Thành công; truy xuất thấy đủ 2 cấp |
| T-PR-06 | Thêm cùng một thành phần hai lần | Chặn |
| T-PR-07 | Gây lỗi giữa chừng (một chai bị người khác trừ cạn khi đang lưu) | Rollback: tồn nguồn về đúng, dung dịch bị Void, sổ cái có `Reversal` |
| T-PR-08 | Dung dịch `ReviewStatus = Rejected` dùng làm nguyên liệu/dùng thử nghiệm | Chặn |
| T-PR-09 | Reviewer trùng người pha duyệt | Từ chối (BR-08) |

**Theo dõi lượng còn lại (yêu cầu 3)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-RM-01 | Sau chuỗi nhập/pha/dùng/điều chỉnh | Bất biến `Remaining = Σ ledger` đúng; thanh còn lại và trạng thái hiển thị đúng |
| T-RM-02 | Hai Analyst cùng trừ một chai song song (script gọi đồng thời) | Không bao giờ âm; sau `LAB-S02` số liệu khớp sổ cái |
| T-RM-03 | Owner sửa tay `RemainingQty` trên SharePoint | `LAB-S02` khôi phục theo sổ cái, ghi audit, gửi cảnh báo |
| T-RM-04 | Nhiều giao dịch số lẻ (0,1 + 0,2 g …) | Không lệch số thực (làm tròn 4 số lẻ) |
| T-RM-05 | Qua ngày hết hạn | `LAB-S01` đánh dấu Expired; không dùng được; vẫn truy xuất được |
| T-RM-06 | Hoá chất có tồn chuẩn 1.000 mL, ngưỡng mặc định 20%; còn 190 mL rồi 210 mL | 190 mL: hiện "Cần mua thêm" ở KPI, tab gộp và email; 210 mL: không cảnh báo |
| T-RM-08 | Đặt `LowStockPct = 50` riêng cho một hoá chất, giữ mặc định ở hoá chất khác | Hoá chất riêng cảnh báo ở 50%, các hoá chất khác ở 20%; đổi `DefaultLowStockPct` chỉ ảnh hưởng nhóm dùng mặc định |
| T-RM-09 | Dùng hết sạch mọi chai của một hoá chất (còn 0) | Vẫn xuất hiện ở "Cần mua thêm" với 0% (không biến mất khỏi danh sách) |
| T-RM-10 | Chưa đặt `ParLevelQty`: nhập thêm chai làm tồn tổng vượt `PeakQty`; sau đó đặt `ParLevelQty` | `PeakQty` tăng theo lần nhập; khi có `ParLevelQty` thì mốc 100% dùng giá trị này |
| T-RM-07 | Dùng hết đúng bằng tồn | `Status = Empty`, ẩn khỏi danh sách "đang dùng", vẫn tra cứu |

**Ghi nhận sử dụng và truy xuất (yêu cầu 4)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-US-01 | Gắn 2 dung dịch vào 1 biên bản | 2 dòng `LabTestUsage`, trừ đúng, sổ cái `TestUse` có `RefCode = số biên bản` |
| T-US-02 | `purpose = Test` không có số biên bản | Từ chối |
| T-US-03 | Dùng vượt tồn | Từ chối, tồn không đổi |
| T-TR-01 | Truy xuất bằng mã `PC-…` | Đủ: thông tin, công thức, số lô NSX, link COA, danh sách biên bản (mở được link) |
| T-TR-02 | Truy xuất bằng mã `IN-…` qua 3 cấp pha | Thấy mọi dung dịch hậu duệ và mọi biên bản |
| T-TR-03 | Biên bản qua dung dịch hậu duệ | Hiện cột "qua dung dịch" |
| T-TR-04 | Mã không tồn tại / sai định dạng / chuỗi rất dài | Thông báo thân thiện, không lỗi, không điều hướng |
| T-TR-05 | Truy xuất đối tượng đã Empty/Expired/Disposed | Vẫn đầy đủ |

**QR và mã vạch (yêu cầu 5)**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-SC-01 | Quét nhãn bằng camera trong app (iOS, Android) | Mở đúng chi tiết trong ≤ 3 giây |
| T-SC-02 | Máy Zebra cầm tay (USB, chế độ HID bàn phím) ở màn Quét — thử cả khi bật và khi tắt hậu tố Enter | Mở đúng chi tiết trong ≤ 1 giây, không cần bấm thêm; không cần quyền camera |
| T-SC-07 | Máy Zebra **1D (laser)** quét mã vạch Code 39 trên nhãn in thật | Đọc đúng mã; mở đúng chi tiết |
| T-SC-08 | Máy 2D hoặc điện thoại quét QR trên cùng nhãn | Đọc đúng mã |
| T-SC-09 | Bộ gõ tiếng Việt (Unikey/Telex) đang bật khi quét; Caps Lock bật | Mã vẫn nhận đúng, hoặc app báo "Không nhận ra mã" rõ ràng (không mở sai đối tượng) |
| T-SC-03 | QR `DeepLink` quét bằng camera điện thoại | Mở app đúng mã (cả trường hợp chưa đăng nhập) |
| T-SC-04 | Nhãn in 50 × 30 mm | Quét được ở 20–30 cm; thử dán lên chai cong, nhãn ướt, ánh sáng yếu |
| T-SC-05 | Quét mã lạ, URL ngoài, chuỗi 10.000 ký tự | App không treo, không mở trang ngoài |
| T-SC-06 | Quét ngay sau khi tạo (chưa nhận dữ liệu) | Tìm thấy hoặc báo rõ ràng, không lỗi |

**Bảo mật**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-SEC-01 | Gửi payload có trường giả `actor`/email người khác | Bản ghi mang danh tính thật của người gọi |
| T-SEC-02 | Viewer gọi thẳng flow F01–F04 bằng API | Từ chối + `LabAudit` Rejected |
| T-SEC-03 | Analyst sửa/xoá item `LabLots`, `LabLedger` trên giao diện SharePoint | Không được |
| T-SEC-04 | Analyst/Viewer mở `LabAudit` | Không truy cập được |
| T-SEC-05 | Người không có trong `LabRoles` mở app | Màn `scrNoAccess`, không dữ liệu |
| T-SEC-06 | Analyst gọi `Adjust`/`Dispose`/`Void` | Từ chối |
| T-SEC-07 | `RequestId` = `' or 1 eq 1 or '`; tên chứa `'`, `=cmd\|'/c calc'!A1`, `<script>` | Từ chối `RequestId`; chuỗi khác lưu nguyên văn, không làm hỏng truy vấn, không thực thi |
| T-SEC-08 | `reportUrl` ngoài danh sách host cho phép (khi đã cấu hình) | Từ chối |
| T-SEC-09 | Người ngoài nhóm bảo mật mở link app | Không mở được |
| T-SEC-10 | Đổi chủ flow / đổi mật khẩu tài khoản dịch vụ | Flow không hỏng ngoài dự kiến; có cảnh báo khi connection lỗi |
| T-SEC-11 | Tìm trong run history/ audit có dữ liệu không cần thiết | Không có bí mật/token |
| T-SEC-12 | Theo dõi mạng khi sinh QR | Chỉ gọi tới nguồn đã duyệt; payload chỉ là mã nội bộ |

**Hiệu năng và dùng được**

| ID | Kịch bản | Kỳ vọng |
|---|---|---|
| T-PF-01 | 5.000 chai, 40.000 dòng sổ cái: mở Tồn kho, tìm theo mã/tên/số lô | < 3 giây; không cảnh báo delegation |
| T-PF-02 | F01 với 20 chai; F02 với 30 thành phần | Mỗi flow < 60 giây |
| T-PF-03 | Mở Trang chủ | < 4 giây |
| T-UX-01 | Analyst mới, không hướng dẫn: nhập 1 lô và pha 1 dung dịch | ≤ 5 phút, không cần hỏi |
| T-UX-02 | Điện thoại: quét → xem tồn → ghi dùng | ≤ 3 thao tác |
| T-UX-03 | Accessibility checker, tương phản, màn hình điện thoại/máy tính bảng | 0 lỗi nghiêm trọng; không cuộn ngang |
| T-UX-04 | Tiếng Việt có dấu trong app, email, nhãn | Hiển thị đúng |

### 6.3 Tiêu chí nghiệm thu theo yêu cầu

| Yêu cầu | Đạt khi |
|---|---|
| 1. Đăng ký hoá chất đầu vào | T-IN-01…10 đạt |
| 2. Đăng ký pha chế | T-PR-01…09 đạt |
| 3. Theo dõi lượng còn lại | T-RM-01…10 đạt; bất biến không vi phạm trong 2 tuần chạy thử |
| 4. Truy xuất biên bản qua mã hoá chất pha | T-US-01…03, T-TR-01…05 đạt |
| 5. QR / mã vạch | T-SC-01…09 đạt trên thiết bị thật của phòng lab (đúng máy Zebra và máy in nhãn đang dùng) |
| Bảo mật | T-SEC-01…12 đạt, không còn rủi ro mức Cao |

## 7. Câu hỏi mở (cần anh/đơn vị xác nhận)

1. **Biên bản thử nghiệm** (xem định nghĩa ở [01 mục 3a](01-Thiet-ke-tong-the.md)) trong phòng lab anh gọi là gì (biên bản, báo cáo, phiếu kết quả…) và **hiện lưu ở đâu** (thư viện SharePoint, hệ thống khác, bản giấy)? Quyết định cách gắn liên kết và có cần tích hợp không.
2. **Một chai một mã QR** có đúng với cách làm việc không, hay theo lô?
3. **Có cần duyệt**: kiểm nhập (Quarantine → Release) và duyệt dung dịch pha (4 mắt)? Hiện thiết kế sẵn, mặc định tắt kiểm nhập, bật duyệt dung dịch ở mức ghi nhận.
4. **Máy quét Zebra** đang dùng là model nào (ví dụ LS2208, DS2208, DS2278…) — loại **1D (laser) hay 2D (imager)**, nối USB hay Bluetooth, nối với PC chạy trình duyệt hay Power Apps for Windows? **Máy in nhãn** nào và **kích thước nhãn**?
5. **Quy mô**: bao nhiêu chai/dung dịch mỗi năm, bao nhiêu người dùng đồng thời?
6. **Tiêu chuẩn áp dụng** (ISO/IEC 17025, GLP…) và **thời gian lưu hồ sơ**?
7. **Môi trường Power Platform**: có Dataverse/Solution không, loại giấy phép, có tài khoản dịch vụ và hộp thư gửi cảnh báo không?
8. **Đơn vị**: có cần các đơn vị khác (mol, %, đương lượng) hoặc chất tồn kho đếm theo cái (pcs) không?
9. Có cần **ảnh GHS/cảnh báo nguy hiểm** trên nhãn, và **kiểm soát chất thuộc diện đặc biệt** (tiền chất, chất độc) không?
10. **Ngôn ngữ**: chỉ tiếng Việt hay song ngữ?
11. **Cảnh báo sắp hết:** mốc 100% lấy từ *lượng tồn chuẩn* của từng hoá chất (hoặc tồn cao nhất đã đạt) và ngưỡng mặc định 20% có hợp lý không? Hay anh muốn so với từng chai, hoặc dùng số lượng tuyệt đối?

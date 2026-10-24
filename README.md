# LabChem — Quản lý hoá chất phòng lab (SharePoint + Power Apps + Power Automate)

Thiết kế ứng dụng đăng ký hoá chất đầu vào, đăng ký pha chế, theo dõi lượng còn lại, truy xuất biên bản thử nghiệm qua mã hoá chất pha, quét QR/mã vạch.

## Đọc theo thứ tự

**Khó đọc file .md? Mở [LabChem-TongQuan.html](LabChem-TongQuan.html) bằng trình duyệt** — một trang gồm phần tổng quan dễ đọc (kèm ảnh giao diện) và toàn bộ 5 tài liệu bên dưới (bấm để mở từng cái).

| Tài liệu | Nội dung |
|---|---|
| [docs/01-Thiet-ke-tong-the.md](docs/01-Thiet-ke-tong-the.md) | Phạm vi, ánh xạ 5 yêu cầu → tính năng, kiến trúc, luồng nghiệp vụ, quyết định thiết kế, lộ trình |
| [docs/02-Mo-hinh-du-lieu.md](docs/02-Mo-hinh-du-lieu.md) | 10 SharePoint list, từng cột, quy tắc nghiệp vụ, mã QR (sinh tự động từ schema) |
| [docs/03-Power-Automate.md](docs/03-Power-Automate.md) | 7 flow: bước chi tiết, biểu thức, xử lý lỗi, chống ghi trùng |
| [docs/04-Power-Apps.md](docs/04-Power-Apps.md) | Design tokens, 11 màn hình, công thức Power Fx |
| [docs/05-Bao-mat-va-Kiem-thu.md](docs/05-Bao-mat-va-Kiem-thu.md) | Phân quyền, mối đe doạ, rủi ro, danh sách go-live, 65 ca kiểm thử, câu hỏi mở |
| [mockup/index.html](mockup/index.html) | Giao diện tham chiếu — mở bằng trình duyệt (cần mạng để vẽ QR thật; không có mạng thì dùng hình thay thế) |

## Triển khai

1. Chốt các **câu hỏi mở** ở [05 §7](docs/05-Bao-mat-va-Kiem-thu.md).
2. Tạo site SharePoint, cài `PnP.PowerShell` (PowerShell 7.2+), đăng ký Entra app cho PnP, rồi:
   ```powershell
   ./sharepoint/New-LabChemLists.ps1 -DryRun                      # kiểm tra schema, không kết nối
   ./sharepoint/New-LabChemLists.ps1 -SiteUrl https://<tenant>.sharepoint.com/sites/LabChem `
       -ClientId <guid> -SeedData -AdminEmail <email-admin>
   ./sharepoint/New-LabChemLists.ps1 -SiteUrl … -ClientId <guid> `
       -ApplyPermissions -ServiceAccountUpn <svc-labchem@…>       # tách quyền: chỉ đọc cho người dùng
   ```
3. Dựng flow theo [03](docs/03-Power-Automate.md) (trong một Solution), rồi app theo [04](docs/04-Power-Apps.md).
4. Chạy bộ kiểm thử ở [05 §6](docs/05-Bao-mat-va-Kiem-thu.md) trước khi mở cho người dùng.

## Trạng thái hiện tại — đã kiểm tra gì, chưa kiểm tra gì

| Hạng mục | Trạng thái |
|---|---|
| Schema + script SharePoint | Đã kiểm tra cú pháp PowerShell và sinh/parse XML của 99 cột (`-DryRun`). **Chưa chạy trên SharePoint thật.** |
| Mã vạch Code 39 trên nhãn | Thuật toán đã kiểm chứng bằng bộ giải mã ZXing. Công thức Power Fx chưa chạy trong Studio; chưa thử với máy Zebra thật. |
| `docs/02` | Sinh từ schema nên khớp script. |
| Mockup | Đã mở bằng trình duyệt headless và xem ảnh chụp các màn chính. |
| Công thức Power Fx, flow | **Chưa chạy** trong Power Apps/Power Automate (chưa có tenant/environment). Danh sách điểm cần xác nhận ở [04 §10](docs/04-Power-Apps.md). |
| QR | Mặc định dùng dịch vụ công cộng **chỉ để chạy thử**; phải thay trước go-live (rủi ro R-03). |

## Cấu trúc thư mục

```
sharepoint/  LabChem.Schema.ps1 (nguồn sự thật)  ·  New-LabChemLists.ps1
tools/       Build-DataModelDoc.ps1  — sinh lại docs/02 sau khi sửa schema
             Build-Overview.mjs      — sinh LabChem-TongQuan.html (cd tools && npm install && node Build-Overview.mjs)
docs/        01…05
mockup/      index.html
```

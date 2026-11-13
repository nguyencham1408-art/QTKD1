# HỆ THỐNG AI AGENT THẨM ĐỊNH ĐỐI TÁC PHÂN PHỐI - CÔNG TY GIA DỤNG ĐẠI THÀNH

Hệ thống AI Agent tự động hóa quá trình tiếp nhận, sàng lọc, đối soát địa bàn, kiểm soát rủi ro công nợ và chấm điểm hồ sơ ứng viên đối tác phân phối cho Công ty Gia dụng Đại Thành trên môi trường Localhost.

---

## 1. Cấu Trúc Dự Án

```
QTKD1/
│── config/
│   ├── policies.json                 # Bộ quy chuẩn công nợ, bảo hộ địa bàn, tiêu chuẩn kỹ thuật & trọng số
│   └── existing_partners.json        # CSDL đại lý hiện hữu, điểm bán bảo hộ và danh sách Blacklist
│── samples/
│   └── candidate_applications.json   # 3 hồ sơ ứng viên mẫu đại diện cho 3 tình huống thực tế
│── public/
│   └── index.html                    # Dashboard điều hành giao diện web trực quan cho Trưởng phòng
│── server.ps1                        # Backend Engine tích hợp Multi-Agent xử lý trên Localhost (Port 5000)
│── start.bat                         # File kích hoạt 1-click (dành cho Windows)
│── run.ps1                           # Script khởi chạy bằng PowerShell
└── README.md                         # Hướng dẫn chi tiết
```

---

## 2. Mô Hình Multi-Agent Giải Quyết Bài Toán Của Đại Thành

Hệ thống thay thế hoàn toàn việc nhân viên phải đi hỏi thủ công các phòng ban Kinh doanh, Vận hành, Tài chính:

1. **Entity Deduplication Agent (Chống gian lận thực thể):**
   - Đối soát tự động Mã số thuế (MST), Tên người đại diện, Số điện thoại với CSDL đại lý.
   - Phát hiện các trường hợp "ve sầu thoát xác" hoặc đơn vị từng nợ xấu trong quá khứ (`blacklisted_bad_debt`).
2. **Territory Protection Agent (Phòng Kinh doanh):**
   - Tính toán khoảng cách địa lý thực tế (Công thức Haversine theo tọa độ GPS).
   - Kiểm tra bán kính bảo hộ điểm bán (Quy chuẩn tối thiểu 2.0 km nội thành). Phát hiện ngay tình trạng trùng địa bàn với đại lý hiện có.
3. **Credit Risk Agent (Phòng Tài chính):**
   - Đối chiếu hạn mức công nợ và số ngày ân hạn với chính sách đại lý thử việc (Tối đa 100 triệu, 7 ngày).
   - Ngăn chặn tình trạng đại lý dùng cam kết doanh số ảo để đòi hạn mức công nợ vượt khung.
4. **Operations & Warranty Agent (Phòng Vận hành):**
   - Thẩm định năng lực kỹ thuật: Số lượng thợ kỹ thuật đạt chuẩn (tối thiểu 2 thợ), SLA cam kết xử lý sự cố (<= 48h), kho bãi linh kiện gia dụng.
5. **Master Decision Agent (Trợ lý Trưởng phòng):**
   - Tính điểm tổng hợp theo ma trận trọng số (Thang điểm 100).
   - Tự động xuất **Checklist Điều kiện Tiên quyết phải xác minh** trước khi Trưởng phòng đặt bút ký.

---

## 3. Cách Khởi Chạy Trên Localhost

### Cách 1: Chạy nhanh bằng 1-Click
Nhấp đúp chuột vào file **`start.bat`**. 
Trình duyệt sẽ tự động mở trang web điều hành tại:
👉 **`http://localhost:5000`**

### Cách 2: Khởi chạy bằng PowerShell
Mở PowerShell trong thư mục dự án và chạy:
```powershell
.\run.ps1
```
Hoặc:
```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Port 5000
```

---

## 4. Các Tính Năng Trên Giao Diện Web

1. **Bảng KPI Điều hành:** Thống kê tổng số hồ sơ, số hồ sơ Ưu tiên Tiến hành, Chờ xác minh, và Bị từ chối.
2. **Nút "Kích hoạt AI Thẩm định":** Chạy toàn bộ pipeline Multi-Agent qua danh sách hồ sơ trong vài mili-giây.
3. **Xem Chi tiết & Điều kiện Xác minh:** Click vào từng hồ sơ để xem chi tiết lý do AI chấm điểm, các cờ cảnh báo (Flags), và danh sách điều kiện cần thẩm định thực địa.
4. **Form Nhập Hồ Sơ Mới:** Cho phép nhân viên nhập trực tiếp hồ sơ đối tác mới để AI thẩm định ngay tại chỗ.
5. **Tra cứu Quy chuẩn & CSDL:** Xem nhanh chính sách công nợ, địa bàn và danh sách các điểm bán hiện có trong hệ thống Đại Thành.


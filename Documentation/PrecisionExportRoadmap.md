# iHomeScan Precision Export Roadmap

Bu hujjat eksport funksiyalarining texnik arxitekturasini belgilaydi. Joriy stage hech qanday PDF, DWG, DXF, IFC, OBJ, FBX yoki USDZ faylini yaratmaydi.

## 1. Yagona eksport manbasi

Eksportlar `PrecisionPlanDocument.currentPlan` dan olinadigan o‘zgarmas `PrecisionExportSnapshot` orqali ishlaydi. Snapshot quyidagilarni saqlaydi:

- metr va `Double` asosidagi real o‘lchamlar;
- qavatlar, xonalar va stabil element IDlari;
- devor, opening, ustun va rigel geometriyasi;
- balandlik/elevation hamda measurement provenance;
- coordinate system, loyiha origin’i va o‘q yo‘nalishlari;
- tahrir reviziyasi va eksport vaqti.

Original RoomPlan JSON, FloorPlan JSON va USDZ o‘zgartirilmaydi. Eksport adapterlari UI yoki SwiftData modelidan bevosita o‘qimaydi.

## 2. Umumiy pipeline

`PrecisionPlanDocument → ExportSnapshotBuilder → ExportValidator → FormatAdapter → AtomicFileWriter`

`ExportValidator` yopilmagan kontur, nonfinite koordinata, noma’lum majburiy balandlik va birlik/scale muammolarini formatga qarab fatal xato yoki warning sifatida qaytaradi. Har bir eksportda unit metadata yoki aniq scale yoziladi.

## 3. Formatlar

### PDF o‘lchov hisoboti

- qavat va xona planlari;
- real dimension chainlar;
- eshik/deraza, ustun va rigel jadvallari;
- verified/manual/derived holati;
- maydon siyosati va revision ma’lumoti;
- A4/A3, scale ko‘rsatkichi va kalibrlash chizig‘i.

### DXF

AutoCAD uchun birinchi ochiq CAD almashinuv formati. Layerlar: walls, openings, columns, beams, dimensions, room labels. Model space metr yoki millimetrda aniq `INSUNITS` bilan yoziladi. Geometriya va annotatsiya alohida layerlarda bo‘ladi.

### DWG

Proprietary formatni qo‘lda yozish rejalashtirilmaydi. Keyingi stage’da litsenziyalangan ODA/RealDWG yechimi yoki nazorat qilinadigan server-side konvertatsiya baholanadi. Manba bir xil DXF/CAD snapshot bo‘ladi.

### IFC (Revit/BIM)

IFC asosiy Revit almashinuv yo‘li bo‘ladi: `IfcProject`, `IfcSite`, `IfcBuilding`, `IfcBuildingStorey`, `IfcSpace`, `IfcWall`, `IfcDoor`, `IfcWindow`, `IfcColumn`, `IfcBeam`. Stabil iHomeScan IDlari deterministic IFC GUID mapping oladi. Noma’lum konstruktiv bog‘lanishlar uydirilmaydi.

### OBJ/MTL

3ds Max va umumiy DCC import uchun sodda triangulated geometry. Metr scale, material guruhlari va floor/element nomlari saqlanadi. Parametrik semantika cheklanganligi metadata manifest bilan ko‘rsatiladi.

### FBX

3ds Max hierarchy, transform va material workflow uchun. SDK/litsenziya va iOS’da lokal yozish imkoniyati alohida spike orqali tekshiriladi; zarur bo‘lsa eksport xizmati ishlatiladi.

### USDZ

Apple Quick Look va RealityKit uchun tahrirlangan 3D sahna. Parametrik modeldan qayta quriladi; original scan USDZ ustiga yozilmaydi.

## 4. Real scale va koordinatalar

- ichki canonical unit: metr;
- CAD chiqishi: konfiguratsiyaga ko‘ra mm yoki metr, metadata majburiy;
- BIM/DCC o‘qlariga aniq transform matrix;
- qavat elevationlari va lokal/project origin alohida;
- rotation export vaqtida geometryga tasodifan bake qilinmaydi;
- round-trip sinovida uzunlik va koordinata tolerance’i tekshiriladi.

## 5. Rejalashtirilgan bosqichlar

1. `PrecisionExportSnapshot` va umumiy validator.
2. PDF measurement report v2.
3. DXF adapter va AutoCAD round-trip QA.
4. IFC adapter va Revit import QA.
5. OBJ/MTL hamda USDZ generatorlari.
6. DWG/FBX SDK va litsenziya qarori, so‘ng adapter.
7. Export center UI, progress, cancellation va share sheet.

## 6. Acceptance sinovlari

- 1000 mm element target dasturda aynan 1000 mm import qilinadi;
- diagonal va nostandart xonalar deformatsiyasiz chiqadi;
- opening, ustun va rigel ID/joylashuvi saqlanadi;
- PDF maydoni va plan maydoni bir xil area policy’dan foydalanadi;
- noma’lum qiymatlar uydirilmaydi;
- eksport original scan assetlarini o‘zgartirmaydi;
- AutoCAD, Revit va 3ds Max’da real round-trip qo‘lda tasdiqlanadi.

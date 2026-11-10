# ORAVENA — مواصفات فيديو الهيدر (جاهزة للمصمم أو لأداة توليد فيديو)

## ما استخلصته من الفيديو المرجعي
- خلفية متدرجة (أزرق فاتح ↔ أزرق داكن/أسود) مع تبديل بين مشاهد فاتحة وداكنة بقطع قطري (wipe).
- كرات زجاجية لامعة بحواف بيضاء وتدرج أزرق، شخصيات مبسطة من كرة + جسم نصف دائري.
- عناصر زجاجية عائمة (لوحات شفافة) وانعكاسات أرضية ناعمة، وكتابة كبيرة نظيفة في النهاية.
- ملاحظة: المرجع عمودي 720×1280 ومدته 26 ثانية، والمطلوب أفقي 1920×1080 و15–20 ثانية، فيجب إعادة تكوين المشاهد وليس قصّ المرجع.

## القصة المصوّرة (18 ثانية، 30fps)
| الزمن | المشهد |
|---|---|
| 0–3s | خلفية أزرق داكن، كرات زجاجية صغيرة (فاتحة/داكنة) تطفو ببطء مع شرارات ضوء ناعمة. |
| 3–7s | الكرات تتجمع وتلتحم لتتحول إلى سن زجاجي ثلاثي الأبعاد يدور ببطء مع انعكاسات سينمائية. |
| 7–11s | قطع قطري (wipe) إلى خلفية بيضاء/أزرق فاتح، السن يلمع ويحيط به حلقات زجاجية. |
| 11–15s | الكرات تدور حول السن وتتجه لليسار (مساحة هادئة يمين الإطار للنص العربي). |
| 15–18s | ظهور شعار ORAVENA بتأثير لمعان زجاجي، ثم يعود الإطار بسلاسة لأول لقطة (Loop). |

## المواصفات
- 1920×1080، 16:9، 30fps، 15–20 ثانية، H.264 (High profile)، بدون صوت (احذف مسار الصوت).
- الألوان: أزرق داكن #0A2A5E، أزرق فاتح #5AA9E6، أبيض #FFFFFF (عدّلها حسب ألوان الشعار الفعلية).
- اترك ثلث الإطار الأيمن تقريباً هادئاً للنص العربي (RTL).
- الحجم المستهدف: ≤ 4MB للديسكتوب، ≤ 1.5MB للموبايل.

## أوامر ffmpeg بعد الحصول على الفيديو الخام (master.mp4)
```
# ديسكتوب
ffmpeg -i master.mp4 -an -vf scale=1920:1080 -c:v libx264 -profile:v high -crf 26 -preset slow -pix_fmt yuv420p -movflags +faststart oravena-hero-1080.mp4
# موبايل
ffmpeg -i master.mp4 -an -vf scale=1280:720 -c:v libx264 -crf 29 -preset slow -pix_fmt yuv420p -movflags +faststart oravena-hero-720-mobile.mp4
# صورة Poster
ffmpeg -i master.mp4 -ss 00:00:08 -frames:v 1 -q:v 3 oravena-hero-poster.jpg
```
للّوب السلس: اجعل آخر إطار قريباً جداً من أول إطار (cross-dissolve لآخر 0.5 ثانية).

## برومبت لأداة توليد الفيديو (Veo / Runway / Kling / Sora)
"Cinematic 3D motion graphics, 16:9, 18 seconds, premium dental clinic opening. Translucent glossy glass spheres in light blue and deep navy blue floating smoothly, merging into an elegant realistic glass tooth that rotates slowly with soft studio lighting, subtle caustics and clean reflections. Diagonal wipe transition from dark navy to bright white-blue background. Glass rings orbit the tooth. Ends with a luxurious glass-shine reveal of the logo text 'ORAVENA'. Palette strictly dark blue, light blue, pure white. Clean, minimal, medical-tech, calm and trustworthy. Right third of frame kept empty. No people, no extra text, no sound, seamless loop."
(الشعار الحقيقي يُركَّب فوق الفيديو لاحقاً في برنامج مونتاج لضمان دقة الكتابة.)

## خطوات النشر على GitHub Pages
1. أنشئ مجلد `assets/hero/` داخل المشروع وضع فيه: `oravena-hero-1080.mp4` و`oravena-hero-720-mobile.mp4` و`oravena-hero-poster.jpg`.
2. الصق كتلة `hero-video-snippet.html` كأول عنصر داخل قسم الهيدر في `index.html` (وأزل عنصر الفيديو القديم `oravena-welcome-full.mp4` من الهيدر فقط إن كان يتعارض).
3. أضف `hero-video.css` في آخر ملف CSS الحالي، وغيّر `.hero` إلى كلاس الهيدر الفعلي.
4. أضف `<script src="hero-video.js" defer></script>` قبل `</body>`.
5. `git add . && git commit -m "Add hero video" && git push` — ثم انتظر دقيقة لتحديث GitHub Pages وجرّب بتحديث قسري (Ctrl+Shift+R).

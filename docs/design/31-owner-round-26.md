# الجولة 26: اسم Jamie Roberts، صورة Thumper، وصور بقية السائقين

## ما طلبه المالك
- يُكتب **JAMIE ROBERTS** أسفل صورة Outlaw مثل بقية السائقين، بدل كلمة OUTLAW.
- تُضاف صورة **Thumper** التي أرسلها، ويُكتب تحتها **BRUCE** فقط (الصورة الأصلية مكتوب عليها BRUCE COCHRANE).
- سؤال: هل أستطيع صنع صور بقية السائقين بالطريقة نفسها؟

## ما بُني
- **إزالة الكتابة القديمة:**
  - استعملت أداة LaMa لإعادة رسم ما تحت الحروف (نموذج مفتوح المصدر يعمل على جهازي، `tools/portraits/unletter.py`).
  - أُزيلت كلمة OUTLAW من صورة Outlaw، وكلمة COCHRANE من صورة Thumper.
- **الحروف الجديدة من حروفك أنت** (`tools/portraits/names.py`):
  - كل حرف مقصوص من أسماء صورك نفسها:
    - B وR وE وO وA من BRUCE COCHRANE.
    - M وI من GRIMM.
    - S من MARCUS.
    - T من كلمة OUTLAW القديمة.
  - لا يوجد J في أي اسم، فصنعته من حرف U في BRUCE بقص ساقه اليسرى.
  - الحروف بالحجم نفسه على خط صاعد، بإطار أسود وظل، وخط أحمر تحتها مثل الباقين.
- **Thumper:**
  - كلمة BRUCE كما رسمتها، والخط الأحمر تحتها قصير على قدر الكلمة.
  - في شاشة الاختيار يظهر بعد السيارات الخمس، بصورته وأرقامه من فصل التصميم الأول:
    - السرعة 6، الدروع 7، التحكم 5، السلاح الخاص 6.
    - السلاح الخاص Megafire، والمساند Drive-By، والسائق Bruce.
  - المنصة فارغة وعليها «COMING SOON». إن ضغطت اختيار يرفض بصوت واهتزاز، لأن سيارته لم تُبنَ بعد.
  - صورته بعد الاختيار جاهزة، وتظهر حين تُبنى السيارة.
- مصدر الصورة محفوظ في `docs/reference/portraits/owner_thumper.webp`، وكل الصور تُبنى من جديد بأمر واحد: `tools/portraits/build.sh`.

## عن صور بقية السائقين (الجواب الصريح)
**لا أستطيع رسمها بنفسي بهذه الجودة.** ما فعلته في الصور الست تعديلٌ على رسوماتك:
- إزالة أشياء منها.
- تغيير الألوان.
- قص الحروف وإعادة تركيبها.

رسم شخصية جديدة من الصفر بهذا الأسلوب يحتاج أداة توليد صور، وهناك طريقتان:
1. **أنت تولّدها بالأداة التي صنعت بها هذه الصور (الأفضل).** الوصف الجاهز لكل سائق في الأسفل، والصور تبقى بأسلوب واحد.
   - أرفق مع كل طلب صورتين:
     - مثالاً جاهزاً للأسلوب، مثل `owner_thumper.webp`.
     - صورة السائق الأصلية من `docs/reference/` (مذكورة بجانب كل اسم).
   - ثم أرسلها لي، وأصلح ما يلزم كما فعلت هذه الجولة: الملابس، الخلفية، الاسم إن أخطأت الأداة في كتابته.
2. **أنا أولّدها هنا بأداة مدفوعة** (Higgsfield أو غيرها). هذا يصرف من رصيدك، ورصيد Higgsfield حوالي 0.17 فقط، وأظنه لا يكفي (لست متأكداً من سعر الصورة). لن أفعلها إلا بموافقتك.

### الوصف الموحد (يُنسخ كما هو، ثم يُملأ [CHARACTER] و[NAME] و[ACTION])
```
Two-panel character select card for a vehicular combat game, two portrait panels side by side separated by a thin white line,
each panel with a thick dark red painted frame. Gritty modern American comic book art: heavy black ink, cross-hatching,
painted texture, dark desaturated colours, red-orange rim light from the side. Match the style of the attached example card exactly.
LEFT panel (before the pick): [CHARACTER], calm and menacing, bust from the head to the waist, looking at the viewer,
dark purple grunge background with faint smoke. Across the bottom left, the name "[NAME]" in big red brush lettering with a black
outline, rising slightly to the right, with a red brush swoosh under it.
RIGHT panel (after the pick): the same person, same face, clothes and colours, in an aggressive action pose toward the camera:
[ACTION], snarling or shouting, background of black smoke, fire glow and flying embers. No text in the right panel.
Serious and grim, never cartoonish. Use the attached reference picture for the face, hair, clothes and colours.
```

### كل سائق
عمود [ACTION] اقتراح مني للوضعية بعد الاختيار، غيّره كما تشاء.

| السيارة | [NAME] المقترح | صورة المرجع | [CHARACTER] | [ACTION] |
|---|---|---|---|---|
| Mr. Slam | SIMON WHITTLEBONE | `TMHOSlam.webp` | a thin man in his thirties, thick black-rimmed glasses, combed-back thinning hair, pale blue shirt with a loose dark tie, sleeves rolled up, sweaty, intense manic stare (alive, not a ghost) | slamming a heavy fist toward the camera, a construction hard hat under his other arm |
| Hammerhead | MIKE & STU | `TM2MikeStuSelected.webp`، `Mike_%26_Stu_TM2_Bio.webp` | two reckless teenage slackers side by side, grinning | both leaning out at the camera, one hollering, one throwing devil horns |
| Shadow | RAVEN | `TMBRavenInfobox.webp`، `TMLRavenBio.webp` | a pale young goth woman, long straight black hair with a fringe, dark lipstick, black choker, black clothes | reaching toward the camera with a black-nailed hand, a cold stare |
| Brimstone | JEBIDIAH | `TMBPreacherEntry.webp` | a hard-faced preacher in a wide black brimmed hat and a long black coat with a red lining, stubble, fanatic eyes | raising a worn bible and a stick of dynamite toward the camera, preaching |
| Crimson Fury | AGENT SHEPHERD | `TMHO-Agent_Shepard.webp` | a federal agent in a black suit, white shirt, black tie, shoulder-length dark hair, a phone at his ear | aiming a pistol straight at the camera, badge in his other hand |
| Spectre | KEN MASTERS | `TM2KenSelected.webp`، `Ken_Masters_TM2_Bio.webp` | a young man with dark hair and glasses, a crazed grin | lunging at the camera, laughing, glasses cracked, ghostly blue light around him |
| Twister | AMANDA WATTS | `TMHOMirandaWatts.webp` (Head-On only, see the note) | a young woman racing driver in a white and purple racing suit, helmet under her arm | pulling her helmet on and pointing at the camera, fierce grin |
| Orbital | ALAN VAME | `TM4OrbitalDriver.webp` | a man in a black suit whose left half of the face is bare skull and metal, a skeletal hand | holding a crackling electric orb toward the camera |
| Warthog | COLONEL HALL | `HeadOnWarthog.webp`، `Th.webp` | a military colonel in a khaki shirt and tie with a green army cap, hard jaw | shouting an order and pointing at the camera |
| Junkyard Dog | BILLY RAY | `TMBBillyRayInfobox.webp` | a big gaunt man with long dark hair parted in the middle, heavy brow, deep-set eyes | swinging a spiked bomb on a chain toward the camera |
| Darkside | MR. ASH | **لا توجد صورة سائق عندنا** | — | — |
| Yellow Jacket | CHARLIE KANE JR. | **لا توجد صورة سائق عندنا** | — | — |

## غير متأكد منه / أسئلة
- **Darkside (Mr. Ash) وYellow Jacket (Charlie Kane Jr.):** عندي صور سياراتهما فقط، لا صور السائقين. أرسلها، أو صف لي شكلهما.
- **Twister:** قرارك أن السائقة من TM2 (Amanda Watts)، لكن الصورة الوحيدة عندي من Head-On (Miranda Watts). أي واحدة تريد؟
- **Hammerhead:** صورة TM2 عندي صغيرة جداً (64×128)، فوصف Mike وStu في الجدول عام. صورة أكبر تساعد أداتك.
- الأوصاف في الجدول من الصور المرجعية التي أراها. إن كان شكل أحدهم في ذهنك مختلفاً فغيّره قبل التوليد.
